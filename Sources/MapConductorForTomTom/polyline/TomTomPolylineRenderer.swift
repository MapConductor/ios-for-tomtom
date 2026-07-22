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
        return metersPerPixel * 64.0
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

        // Color/width are immutable on `Line`; re-create when they change.
        if finger.strokeColor != prevFinger.strokeColor || finger.strokeWidth != prevFinger.strokeWidth {
            map?.remove(annotation: polyline)
            return await createPolyline(state: current.state)
        }
        if finger.points != prevFinger.points || finger.geodesic != prevFinger.geodesic {
            polyline.coordinates = coordinates(current.state.points, geodesic: current.state.geodesic)
        }
        return polyline
    }

    override func removePolyline(entity: PolylineEntity<TomTomActualPolyline>) async {
        if let line = entity.polyline {
            map?.remove(annotation: line)
        }
    }
}
