import CoreLocation
import MapConductorCore

// TomTom Orbis uses CoreLocation's `CLLocationCoordinate2D` directly, so the
// conversions to/from MapConductor's `GeoPoint` are trivial.
// NOTE: `CLLocationCoordinate2D` carries no altitude, so it is dropped/zeroed on round-trip.

extension GeoPointProtocol {
    func toCoordinate() -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension CLLocationCoordinate2D {
    func toGeoPoint() -> GeoPoint {
        GeoPoint(latitude: latitude, longitude: longitude, altitude: 0)
    }
}
