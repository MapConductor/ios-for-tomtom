import CoreLocation
import Foundation
import MapConductorCore
import TomTomSDKMapDisplay

/// Renders MapConductor circles as native TomTom `Polygon`s built from the core `circleToRing`
/// ring, mirroring `TomTomPolygonRenderer` and matching how the Google provider draws circles
/// (a filled ring polygon).
///
/// TomTom's native `Polygon` is coordinate-constrained (one ring, longitudes within +/-180), so
/// the ring is normalized and split at the antimeridian with the ring-aware
/// `splitRingByMeridian`; each fragment becomes one native polygon. The first fragment is the
/// entity tracked by the core `CircleManager`; any extra fragments (only present when the circle
/// crosses +/-180) are tracked per circle id in `extraFragments` so updates/removal stay correct.
///
/// This intentionally replaces the earlier fill-`Circle` + stroke-`Line` composite, which had
/// two problems:
///   1. `Line` draws a default red outline; on a thin semi-transparent stroke that red bled into
///      the blue line and the outline looked purple. `Polygon.outlineColor` is a true outline
///      (same path the working polygon renderer uses), so the stroke renders in its real color.
///   2. TomTom's `Circle`/`Line` have immutable geometry/appearance, so every drag frame
///      re-created both native overlays — which flickers. `Polygon` exposes mutable
///      `coordinates`/`fillColor`/`outlineColor`, so a drag mutates the ring in place with no
///      add/remove and therefore no flicker. Only a stroke-width change (immutable) re-creates.
@MainActor
final class TomTomCircleRenderer: AbstractCircleOverlayRenderer<TomTomActualCircle> {
    weak var map: TomTomMap?

    /// 円の描画（追加/更新/カメラ移動）が終わるたびに呼ばれる。
    /// 円は毎フレーム作り直されて最前面に来るため、ここでポリラインを最前面へ戻す。
    var onAfterRender: (() async -> Void)?

    /// 先頭以外の断片（±180 を跨ぐ円のみ）。circle id ごとに管理し、更新・削除時に一緒に扱う。
    private var extraFragments: [String: [TomTomActualCircle]] = [:]

    init(map: TomTomMap?) {
        super.init()
        self.map = map
    }

    override func onPostProcess() async {
        await onAfterRender?()
    }

    /// コア共通の `circleToRing` でリングを生成し、normalize + `splitRingByMeridian` で
    /// ±180 で分割した断片（閉じたリング）を返す。
    private func ringFragments(_ state: CircleState) -> [[CLLocationCoordinate2D]] {
        let ring = circleToRing(
            center: state.center,
            radiusMeters: state.radiusMeters,
            geodesic: state.geodesic
        )
        return splitRingByMeridian(ring.map { $0.normalize() }, geodesic: state.geodesic)
            .filter { $0.count >= 3 }
            .map { fragment in
                closeRing(fragment).map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
            }
    }

    override func createCircle(state: CircleState) async -> TomTomActualCircle? {
        guard let map else { return nil }
        var polygons: [TomTomActualCircle] = []
        for coordinates in ringFragments(state) {
            var options = PolygonOptions(coordinates: coordinates)
            options.fillColor = state.fillColor
            options.outlineColor = state.strokeColor
            options.outlineWidth = state.strokeWidth
            options.isSelectable = state.clickable
            guard let polygon = try? map.addPolygon(options: options) else { continue }
            // "circle-" 接頭辞でタップ時に円として振り分ける（TomTomMapView 参照）。
            polygon.tag = "circle-\(state.id)"
            polygons.append(polygon)
        }
        guard let primary = polygons.first else { return nil }
        extraFragments[state.id] = Array(polygons.dropFirst())
        return primary
    }

    override func updateCircleProperties(
        circle: TomTomActualCircle,
        current: CircleEntity<TomTomActualCircle>,
        prev: CircleEntity<TomTomActualCircle>
    ) async -> TomTomActualCircle? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint
        let state = current.state

        // `Polygon.coordinates` は stored property でエンジンにブリッジされず、代入しても
        // 再描画されない（＝エッジのドラッグに追従しない）。outlineWidth も options 側のみで
        // immutable。したがって幾何 / 線幅が変わったら作り直す必要がある。
        // 空フレームでちらつかないよう「新しい polygon を追加してから古いものを削除」する。
        if finger.center != prevFinger.center ||
            finger.radiusMeters != prevFinger.radiusMeters ||
            finger.geodesic != prevFinger.geodesic ||
            finger.strokeWidth != prevFinger.strokeWidth {
            let oldExtras = extraFragments[state.id] ?? []
            let replacement = await createCircle(state: state)
            map?.remove(annotation: circle)
            for fragment in oldExtras {
                map?.remove(annotation: fragment)
            }
            if replacement == nil {
                extraFragments.removeValue(forKey: state.id)
            }
            return replacement
        }

        // fillColor / outlineColor は computed で即時反映されるため in-place 更新できる。
        if finger.fillColor != prevFinger.fillColor {
            circle.fillColor = state.fillColor
            extraFragments[state.id]?.forEach { $0.fillColor = state.fillColor }
        }
        if finger.strokeColor != prevFinger.strokeColor {
            circle.outlineColor = state.strokeColor
            extraFragments[state.id]?.forEach { $0.outlineColor = state.strokeColor }
        }
        if finger.clickable != prevFinger.clickable {
            circle.isSelectable = state.clickable
            extraFragments[state.id]?.forEach { $0.isSelectable = state.clickable }
        }
        return circle
    }

    override func removeCircle(entity: CircleEntity<TomTomActualCircle>) async {
        if let polygon = entity.circle {
            map?.remove(annotation: polygon)
        }
        for fragment in extraFragments.removeValue(forKey: entity.state.id) ?? [] {
            map?.remove(annotation: fragment)
        }
    }
}
