import CoreLocation
import Foundation
import MapConductorCore
import TomTomSDKMapDisplay

/// Renders MapConductor polylines as native TomTom `Line`s.
///
/// TomTom's `Line` only exposes mutable `coordinates`/`isVisible`; color/width are set at creation,
/// so a color/width change re-creates the line. Geodesics are approximated by interpolating the
/// coordinate list (TomTom draws straight segments between coordinates).
@MainActor
final class TomTomPolylineRenderer: AbstractPolylineOverlayRenderer<TomTomActualPolyline> {
    weak var map: TomTomMap?

    init(map: TomTomMap?) {
        super.init()
        self.map = map
    }

    private func maxSegmentLengthMeters() -> Double {
        let zoom = map?.cameraProperties.zoom ?? 11.0
        let metersPerPixel = 40_075_016.686 / (256.0 * pow(2.0, zoom))
        // ズームアウト時にセグメントが粗くなりすぎて geodesic が直線同然になるのを防ぐ
        // （android-sdk と同じ上限。polygon は三角形分割のちらつき対策で polyline より粗め）。
        return min(metersPerPixel * 64.0, 50_000.0)
    }

    private func coordinates(_ points: [GeoPointProtocol], geodesic: Bool) -> [CLLocationCoordinate2D] {
        let geo = geodesic
            ? createInterpolatePoints(points, maxSegmentLength: maxSegmentLengthMeters())
            : createLinearInterpolatePoints(points)
        return geo.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    override func createPolyline(state: PolylineState) async -> TomTomActualPolyline? {
        guard let map else { return nil }
        var options = LineOptions(coordinates: coordinates(state.points, geodesic: state.geodesic))
        options.lineColor = state.strokeColor
        options.lineWidth = state.strokeWidth
        // Line は既定で赤い枠線（outline）を描くため無効化（他プロバイダに合わせる）。
        options.outlineAppearance.outlineWidth = 0.0
        let line = try? map.addLine(options: options)
        line?.tag = state.id
        return line
    }

    override func updatePolylineProperties(
        polyline: TomTomActualPolyline,
        current: PolylineEntity<TomTomActualPolyline>,
        prev: PolylineEntity<TomTomActualPolyline>
    ) async -> TomTomActualPolyline? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        // `Line` は lineColor/lineWidth が options 側のみで immutable。さらに `coordinates` は
        // stored property でエンジンにブリッジされず、代入しても再描画されない（＝マーカーの
        // ドラッグに追従しない）。よって見た目に関わる変更はすべて作り直す。
        if finger.strokeColor != prevFinger.strokeColor ||
            finger.strokeWidth != prevFinger.strokeWidth ||
            finger.points != prevFinger.points ||
            finger.geodesic != prevFinger.geodesic {
            map?.remove(annotation: polyline)
            return await createPolyline(state: current.state)
        }
        return polyline
    }

    override func removePolyline(entity: PolylineEntity<TomTomActualPolyline>) async {
        if let line = entity.polyline {
            map?.remove(annotation: line)
        }
    }

    /// 既存の全ラインを削除して再追加し、最前面（他アノテーションの上）へ移動する。
    /// TomTom には z-index / 並び替え API が無く、描画順は追加順だけで決まるため、
    /// 下のレイヤー（円/ポリゴン）が再生成された後に呼び出して重なり順を回復する。
    func reAddOnTop(_ entities: [PolylineEntity<TomTomActualPolyline>]) async {
        for entity in entities {
            if let line = entity.polyline { map?.remove(annotation: line) }
            entity.polyline = await createPolyline(state: entity.state)
        }
    }
}
