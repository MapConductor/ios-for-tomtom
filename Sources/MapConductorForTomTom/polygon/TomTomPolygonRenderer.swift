import CoreLocation
import Foundation
import MapConductorCore
import TomTomSDKMapDisplay

/// Renders MapConductor polygons as native TomTom `Polygon`s.
/// NOTE: TomTom Orbis polygons do not support holes; only the outer ring is drawn.
@MainActor
final class TomTomPolygonRenderer: AbstractPolygonOverlayRenderer<TomTomActualPolygon> {
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

    private func ring(_ points: [GeoPointProtocol], geodesic: Bool) -> [CLLocationCoordinate2D] {
        let geo = geodesic
            ? createInterpolatePoints(points, maxSegmentLength: maxSegmentLengthMeters())
            : createLinearInterpolatePoints(points)
        return geo.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    override func createPolygon(state: PolygonState) async -> TomTomActualPolygon? {
        guard let map else { return nil }
        var options = PolygonOptions(coordinates: ring(state.points, geodesic: state.geodesic))
        options.fillColor = state.fillColor
        options.outlineColor = state.strokeColor
        options.outlineWidth = state.strokeWidth
        let polygon = try? map.addPolygon(options: options)
        polygon?.tag = state.id
        return polygon
    }

    override func updatePolygonProperties(
        polygon: TomTomActualPolygon,
        current: PolygonEntity<TomTomActualPolygon>,
        prev: PolygonEntity<TomTomActualPolygon>
    ) async -> TomTomActualPolygon? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        // Outline width is immutable on `Polygon`; re-create when it changes.
        if finger.strokeWidth != prevFinger.strokeWidth {
            map?.remove(annotation: polygon)
            return await createPolygon(state: current.state)
        }
        if finger.points != prevFinger.points || finger.geodesic != prevFinger.geodesic {
            polygon.coordinates = ring(current.state.points, geodesic: current.state.geodesic)
        }
        if finger.fillColor != prevFinger.fillColor {
            polygon.fillColor = current.state.fillColor
        }
        if finger.strokeColor != prevFinger.strokeColor {
            polygon.outlineColor = current.state.strokeColor
        }
        return polygon
    }

    override func removePolygon(entity: PolygonEntity<TomTomActualPolygon>) async {
        if let polygon = entity.polygon {
            map?.remove(annotation: polygon)
        }
    }
}
