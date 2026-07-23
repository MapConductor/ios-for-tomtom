import CoreLocation
import Foundation
import MapConductorCore
import TomTomSDKMapDisplay

/// Renders MapConductor circles as a two-layer composite (mirrors the Mapbox renderer's
/// fill-layer + line-layer approach): a native TomTom `Circle` for the fill, plus a `Line`
/// ring for the outline. TomTom's iOS `Circle` has no outline, so the stroke is drawn as a
/// separate polyline ring with a constant pixel width.
///
/// The native `Circle`/`Line` are largely immutable, so any visual change re-creates them.
@MainActor
final class TomTomCircleRenderer: AbstractCircleOverlayRenderer<TomTomActualCircle> {
    weak var map: TomTomMap?

    init(map: TomTomMap?) {
        super.init()
        self.map = map
    }

    /// 中心から半径 radiusMeters の円周を近似する閉じたリング（64分割）。
    private func ringPoints(_ state: CircleState) -> [CLLocationCoordinate2D] {
        let lat = state.center.latitude
        let lng = state.center.longitude
        let segments = 64
        let metersPerDegree = 111_320.0
        let latCorrection = state.geodesic ? cos(lat * .pi / 180.0) : 1.0
        var ring: [CLLocationCoordinate2D] = (0 ..< segments).map { i in
            let angle = 2.0 * .pi * Double(i) / Double(segments)
            let deltaLat = state.radiusMeters / metersPerDegree * cos(angle)
            let deltaLng = state.radiusMeters / (metersPerDegree * latCorrection) * sin(angle)
            return CLLocationCoordinate2D(latitude: lat + deltaLat, longitude: lng + deltaLng)
        }
        if let first = ring.first { ring.append(first) }
        return ring
    }

    private func makeFill(_ state: CircleState) -> TomTomSDKMapDisplay.Circle? {
        guard let map else { return nil }
        let options = CircleOptions(
            coordinate: CLLocationCoordinate2D(latitude: state.center.latitude, longitude: state.center.longitude),
            radius: state.radiusMeters,
            fillColor: state.fillColor
        )
        let fill = try? map.addCircle(options: options)
        fill?.tag = state.id
        return fill
    }

    private func makeStroke(_ state: CircleState) -> TomTomSDKMapDisplay.Line? {
        guard let map, state.strokeWidth > 0 else { return nil }
        // 枠線レイヤー: polyline リング（クリックは塗り側で扱うため選択不可）。
        var options = LineOptions(coordinates: ringPoints(state))
        options.lineColor = state.strokeColor
        options.lineWidth = state.strokeWidth
        // Line は既定で赤い枠線（outline）を描くため、他プロバイダに合わせて無効化する。
        // これが原因で細い半透明線が赤く見えていた。
        options.outlineAppearance.outlineWidth = 0.0
        let stroke = try? map.addLine(options: options)
        stroke?.tag = "circle-stroke-\(state.id)"
        return stroke
    }

    override func createCircle(state: CircleState) async -> TomTomActualCircle? {
        TomTomCircleHandle(fill: makeFill(state), stroke: makeStroke(state))
    }

    override func updateCircleProperties(
        circle: TomTomActualCircle,
        current: CircleEntity<TomTomActualCircle>,
        prev: CircleEntity<TomTomActualCircle>
    ) async -> TomTomActualCircle? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint
        let state = current.state

        // TomTom iOS の `Circle` は radius/center が immutable なので、幾何が変われば作り直すしかない。
        let ringChanged = finger.center != prevFinger.center ||
            finger.radiusMeters != prevFinger.radiusMeters ||
            finger.geodesic != prevFinger.geodesic
        let fillChanged = ringChanged || finger.fillColor != prevFinger.fillColor
        let strokeChanged = ringChanged ||
            finger.strokeColor != prevFinger.strokeColor ||
            finger.strokeWidth != prevFinger.strokeWidth

        guard fillChanged || strokeChanged else { return circle }

        // ドラッグ中は毎フレーム更新されるため、
        //  1) 新レイヤーを先に追加してから旧レイヤーを削除する（空フレームが無く、ちらつかない）。
        //  2) 塗り→枠線 の順に追加して枠線を常に塗りの上に置く
        //     （塗りを後から足すと枠線が半透明の塗りに隠れて「色が違う／枠が描かれない」ように見える）。
        let oldFill = circle.fill
        let oldStroke = circle.stroke
        circle.fill = makeFill(state)
        circle.stroke = makeStroke(state)
        if let oldStroke { map?.remove(annotation: oldStroke) }
        if let oldFill { map?.remove(annotation: oldFill) }
        return circle
    }

    override func removeCircle(entity: CircleEntity<TomTomActualCircle>) async {
        if let fill = entity.circle?.fill { map?.remove(annotation: fill) }
        if let stroke = entity.circle?.stroke { map?.remove(annotation: stroke) }
    }
}
