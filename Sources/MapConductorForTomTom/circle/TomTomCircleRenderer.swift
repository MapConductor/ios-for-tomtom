import CoreLocation
import Foundation
import MapConductorCore
import TomTomSDKMapDisplay

/// Renders MapConductor circles as a single native TomTom `Polygon` (a 64-segment ring),
/// mirroring `TomTomPolygonRenderer` and matching how the Google provider draws circles
/// (a 64-segment filled polygon).
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

    init(map: TomTomMap?) {
        super.init()
        self.map = map
    }

    override func onPostProcess() async {
        await onAfterRender?()
    }

    /// 中心から半径 radiusMeters の円周を近似する 64 分割のリング。
    private func ringPoints(_ state: CircleState) -> [CLLocationCoordinate2D] {
        let lat = state.center.latitude
        let lng = state.center.longitude
        let segments = 64
        let metersPerDegree = 111_320.0
        let latCorrection = state.geodesic ? cos(lat * .pi / 180.0) : 1.0
        return (0 ..< segments).map { i in
            let angle = 2.0 * .pi * Double(i) / Double(segments)
            let deltaLat = state.radiusMeters / metersPerDegree * cos(angle)
            let deltaLng = state.radiusMeters / (metersPerDegree * latCorrection) * sin(angle)
            return CLLocationCoordinate2D(latitude: lat + deltaLat, longitude: lng + deltaLng)
        }
    }

    override func createCircle(state: CircleState) async -> TomTomActualCircle? {
        guard let map else { return nil }
        var options = PolygonOptions(coordinates: ringPoints(state))
        options.fillColor = state.fillColor
        options.outlineColor = state.strokeColor
        options.outlineWidth = state.strokeWidth
        options.isSelectable = state.clickable
        let polygon = try? map.addPolygon(options: options)
        // "circle-" 接頭辞でタップ時に円として振り分ける（TomTomMapView 参照）。
        polygon?.tag = "circle-\(state.id)"
        return polygon
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
            let replacement = await createCircle(state: state)
            map?.remove(annotation: circle)
            return replacement
        }

        // fillColor / outlineColor は computed で即時反映されるため in-place 更新できる。
        if finger.fillColor != prevFinger.fillColor {
            circle.fillColor = state.fillColor
        }
        if finger.strokeColor != prevFinger.strokeColor {
            circle.outlineColor = state.strokeColor
        }
        if finger.clickable != prevFinger.clickable {
            circle.isSelectable = state.clickable
        }
        return circle
    }

    override func removeCircle(entity: CircleEntity<TomTomActualCircle>) async {
        if let polygon = entity.circle {
            map?.remove(annotation: polygon)
        }
    }
}
