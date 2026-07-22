import CoreLocation
import Foundation
import MapConductorCore
import TomTomSDKMapDisplay

private let converter = TomTomZoomAltitudeConverter()

public extension MapCameraPosition {
    /// MapConductor camera → TomTom `CameraUpdate`.
    /// The unified zoom is Google-equivalent, so it is converted to TomTom-native at the target latitude.
    /// `rotation` maps to bearing; tilt is clamped to 0...60.
    func toCameraUpdate() -> CameraUpdate {
        CameraUpdate(
            position: position.toCoordinate(),
            zoom: TomTomZoomAltitudeConverter.googleZoomToTomTomZoom(
                zoom,
                latitude: position.latitude
            ),
            tilt: min(max(tilt, 0.0), 60.0),
            rotation: bearing
        )
    }
}

public extension CameraProperties {
    /// TomTom `CameraProperties` → MapConductor camera.
    /// `zoom` is TomTom-native, converted to the unified (Google) zoom at the camera latitude.
    func toMapCameraPosition(visibleRegion: MapConductorCore.VisibleRegion? = nil) -> MapCameraPosition {
        let altitude = converter.zoomLevelToAltitude(
            zoomLevel: zoom,
            latitude: position.latitude,
            tilt: tilt
        )
        let point = GeoPoint(
            latitude: position.latitude,
            longitude: position.longitude,
            altitude: altitude
        )
        return MapCameraPosition(
            position: point,
            zoom: TomTomZoomAltitudeConverter.tomtomZoomToGoogleZoom(
                zoom,
                latitude: position.latitude
            ),
            bearing: rotation,
            tilt: tilt,
            visibleRegion: visibleRegion
        )
    }
}
