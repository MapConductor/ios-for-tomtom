import CoreLocation
import Foundation
import MapConductorCore
import TomTomSDKMapDisplay

/// TomTom Orbis の穴付きポリゴンは native の `PolygonOverlay`（同心リング）で塗る。
///
/// TomTom の通常 Polygon（`PolygonOptions`）は穴（inner ring）を持てず、Android で使っている
/// keyhole（幅ゼロ橋の単一リング）は iOS の Orbis では塗れない（橋を 1e-3 度まで開いても
/// 不可・凹リング単体は可、を実機確認）。`PolygonOverlay` は「外側の色＋入れ子リングごとの色」
/// を持つため、外周リング（fillColor）→ 穴リング（透明）の入れ子で穴を表現する。
///
/// - 穴なし: native Polygon（fill + outline）1枚。
/// - 穴あり: PolygonOverlay（塗り）＋ 外周・各穴の輪郭を描く stroke-only Polygon（透明 fill）。
///   エンティティ本体は外周輪郭 Polygon。
///
/// TomTom の塗りは巻き方向依存（外周が時計回りだと塗られない）ため、リングは CCW へ正規化する。
/// クリックは同じ tag を付けた Polygon / PolygonOverlay の tag 経由で拾う。
@MainActor
final class TomTomPolygonRenderer: AbstractPolygonOverlayRenderer<TomTomActualPolygon> {
    weak var map: TomTomMap?

    /// 穴ありポリゴンの付随アノテーション（塗り PolygonOverlay＋穴輪郭 Polygon、state.id → 一覧）。
    /// エンティティ本体（外周輪郭 Polygon）とは別に保持し、削除・更新時にまとめて外す。
    private var attachedAnnotationsById: [String: [any Annotation]] = [:]

    init(map: TomTomMap?) {
        super.init()
        self.map = map
    }

    private func maxSegmentLengthMeters() -> Double {
        let zoom = map?.cameraProperties.zoom ?? 11.0
        let metersPerPixel = 40_075_016.686 / (256.0 * pow(2.0, zoom))
        // ズームアウト時にセグメントが粗くなりすぎて geodesic が直線同然になるのを防ぐ
        // （android-sdk と同じ上限。polygon は三角形分割のちらつき対策で polyline より粗め）。
        return min(metersPerPixel * 64.0, 200_000.0)
    }

    /// 補間済み（geodesic 時のみ）の開いたリングを core GeoPoint 列で返す。
    /// 非 geodesic は補間せず生の頂点を使う（android-for-tomtom と同じ。世界マスク級の
    /// リングを線形補間すると過密になり TomTom の描画が失敗するため）。
    private func interpolatedGeo(_ points: [GeoPointProtocol], geodesic: Bool) -> [GeoPointProtocol] {
        let geo = geodesic
            ? createInterpolatePoints(points, maxSegmentLength: maxSegmentLengthMeters())
            : points
        guard let first = geo.first, let last = geo.last else { return geo }
        if geo.count >= 2, first.latitude == last.latitude, first.longitude == last.longitude {
            return Array(geo.dropLast())
        }
        return geo
    }

    /// TomTom へ渡すリング。塗りの巻き方向依存対策として CCW へ正規化する。
    private func ring(_ points: [GeoPointProtocol], geodesic: Bool) -> [CLLocationCoordinate2D] {
        let open = interpolatedGeo(points, geodesic: geodesic)
        return ensureCounterClockwise(open)
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// 複数の穴が重なっている場合は結合（union）して重複を解消する
    /// （他プロバイダと同じ `unionHoles`）。
    private func resolveHoles(_ state: PolygonState) -> PolygonState {
        state.holes.count > 1 ? state.unionHoles() : state
    }

    override func createPolygon(state: PolygonState) async -> TomTomActualPolygon? {
        guard let map else { return nil }
        let resolved = resolveHoles(state)
        let holesGeo = resolved.holes
            .map { interpolatedGeo($0, geodesic: resolved.geodesic) }
            .filter { $0.count >= 3 }

        if holesGeo.isEmpty {
            // 穴なし: native Polygon 1枚で fill + outline。
            var options = PolygonOptions(coordinates: ring(resolved.points, geodesic: resolved.geodesic))
            options.fillColor = resolved.fillColor
            options.outlineColor = resolved.strokeColor
            options.outlineWidth = resolved.strokeWidth
            let polygon = try? map.addPolygon(options: options)
            polygon?.tag = state.id
            return polygon
        }

        // 穴あり: native の PolygonOverlay で塗る。PolygonOverlay は「外側の色 + 入れ子リング
        // ごとの色」を持ち、外周リング（fillColor）→ 穴リング（透明）の入れ子で穴を表現できる。
        // ただし入れ子は同心チェインのため兄弟穴（互いに離れた複数の穴）は 1 枚で表現できない。
        // そこで外周を穴の間の分離線で分割し（分割方式）、各ピース（穴 ≤ 1 個）を 1 枚の
        // PolygonOverlay として描く。分離できない絡み合いはチェインで近似する。
        let outerCoords = ring(resolved.points, geodesic: resolved.geodesic)
        let outerGeo = interpolatedGeo(resolved.points, geodesic: resolved.geodesic)
        let partitions = partitionPolygonByHoles(outer: outerGeo, holes: holesGeo)

        var fillOverlays: [PolygonOverlay] = []
        for partition in partitions {
            var chain: InnerPolygonOptions?
            for hole in partition.holes.reversed() {
                chain = InnerPolygonOptions(
                    fillColor: .color(.clear),
                    coordinates: ensureCounterClockwise(hole)
                        .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) },
                    nestedPolygonOptions: chain
                )
            }
            let outerOptions = InnerPolygonOptions(
                fillColor: .color(resolved.fillColor),
                coordinates: ensureCounterClockwise(partition.outer)
                    .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) },
                nestedPolygonOptions: chain
            )
            do {
                let overlay = try map.addPolygonOverlay(
                    options: PolygonOverlayOptions(outerColor: .color(.clear), innerPolygonOptions: outerOptions)
                )
                overlay.tag = state.id
                fillOverlays.append(overlay)
            } catch {
                NSLog(
                    "[MapConductor][TomTom] addPolygonOverlay failed pieces=%d holes=%d error=%@",
                    partitions.count, partition.holes.count, String(describing: error)
                )
            }
        }

        // 輪郭: 外周 + 各穴（透明 fill の stroke-only Polygon）。
        // エンティティ本体は外周輪郭 Polygon（tag 付き・クリック判定にも使う）。
        var outerOutline = PolygonOptions(coordinates: outerCoords)
        outerOutline.fillColor = .clear
        outerOutline.outlineColor = resolved.strokeColor
        outerOutline.outlineWidth = resolved.strokeWidth
        guard let entityPolygon = try? map.addPolygon(options: outerOutline) else {
            fillOverlays.forEach { map.remove(annotation: $0) }
            return nil
        }
        entityPolygon.tag = state.id

        var attached: [any Annotation] = fillOverlays
        for hole in holesGeo {
            var holeOutline = PolygonOptions(
                coordinates: ensureCounterClockwise(hole)
                    .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            )
            holeOutline.fillColor = .clear
            holeOutline.outlineColor = resolved.strokeColor
            holeOutline.outlineWidth = resolved.strokeWidth
            if let outline = try? map.addPolygon(options: holeOutline) {
                outline.tag = state.id
                attached.append(outline)
            }
        }
        attachedAnnotationsById[state.id] = attached
        return entityPolygon
    }

    override func updatePolygonProperties(
        polygon: TomTomActualPolygon,
        current: PolygonEntity<TomTomActualPolygon>,
        prev: PolygonEntity<TomTomActualPolygon>
    ) async -> TomTomActualPolygon? {
        if current.fingerPrint == prev.fingerPrint {
            return polygon
        }
        // TomTom の Polygon は座標・輪郭幅を in place で変更しても再描画されないため、
        // 変更時は削除→再生成する（穴の有無で構成も変わる。ベクタ描画のため軽量）。
        removeNative(polygon: polygon, id: current.state.id)
        return await createPolygon(state: current.state)
    }

    override func removePolygon(entity: PolygonEntity<TomTomActualPolygon>) async {
        removeNative(polygon: entity.polygon, id: entity.state.id)
    }

    private func removeNative(polygon: TomTomActualPolygon?, id: String) {
        if let polygon {
            map?.remove(annotation: polygon)
        }
        if let attached = attachedAnnotationsById.removeValue(forKey: id) {
            attached.forEach { map?.remove(annotation: $0) }
        }
    }
}
