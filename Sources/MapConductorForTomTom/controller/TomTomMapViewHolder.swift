import CoreGraphics
import CoreLocation
import MapConductorCore
import TomTomSDKMapDisplay
import UIKit

/// Wraps the TomTom `MapView` + `TomTomMap` and exposes coordinate↔screen conversion.
final class TomTomMapViewHolder: MapViewHolderProtocol {
    let mapView: MapView
    let map: TomTomMap

    init(mapView: MapView, map: TomTomMap) {
        self.mapView = mapView
        self.map = map
    }

    func toScreenOffset(position: GeoPointProtocol) -> CGPoint? {
        map.pointForCoordinate(coordinate: position.toCoordinate())
    }

    func fromScreenOffset(offset: CGPoint) async -> GeoPoint? {
        fromScreenOffsetSync(offset: offset)
    }

    func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        map.coordinateForPoint(point: offset)?.toGeoPoint()
    }
}
