import CoreGraphics
import CoreLocation
import MapConductorCore
import TomTomSDKMapDisplay
import UIKit

/// Wraps the TomTom `MapView` + `TomTomMap` and exposes coordinate↔screen conversion.
public final class TomTomMapViewHolder: MapViewHolderProtocol {
    public let mapView: MapView
    public let map: TomTomMap

    init(mapView: MapView, map: TomTomMap) {
        self.mapView = mapView
        self.map = map
    }

    public func toScreenOffset(position: GeoPointProtocol) -> CGPoint? {
        map.pointForCoordinate(coordinate: position.toCoordinate())
    }

    public func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        map.coordinateForPoint(point: offset)?.toGeoPoint()
    }
}
