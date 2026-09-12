import CoreLocation
import Foundation
@_spi(MapConductorDriver) import MapConductorCore
import TomTomSDKMapDisplay

private let converter = TomTomZoomAltitudeConverter()

/// tilt < 0（上向きピッチ）の擬似表現に用いる定数。
/// android-for-tomtom / MapLibre 実装と同一値を用いることで、プロバイダ間で挙動を揃える。
private let negativeTiltTargetDistanceScale = 1.83
private let negativeTiltZoomOffsetAtMaxTilt = -0.9

public extension MapCameraPosition {
    /// MapConductor camera → TomTom `CameraUpdate`.
    /// The unified zoom is Google-equivalent, so it is converted to TomTom-native at the target latitude.
    /// `rotation` maps to bearing; tilt is clamped to 0...60.
    ///
    /// tilt < 0 のときは、TomTom（Mapbox GL 由来のベクターエンジン）が上向きピッチを直接
    /// 表現できないため、地上ターゲットを進行方向（bearing）へ前進させ abs(tilt) の下向き
    /// ピッチで描画することで擬似的に上向き視点を再現する（android-for-tomtom と同一方式）。
    func toCameraUpdate() -> CameraUpdate {
        if tilt >= 0 {
            return CameraUpdate(
                position: position.toCoordinate(),
                zoom: TomTomZoomAltitudeConverter.googleZoomToTomTomZoom(
                    zoom,
                    latitude: position.latitude
                ),
                tilt: min(max(tilt, 0.0), 60.0),
                rotation: CameraBearing.toNativeHeading(bearing)
            )
        }

        let tiltAbsDeg = min(max(abs(tilt), 0.0), 60.0)
        let tiltAbsRad = tiltAbsDeg * .pi / 180.0
        let tomtomZoomForAltitude = TomTomZoomAltitudeConverter.googleZoomToTomTomZoom(
            zoom,
            latitude: position.latitude
        )
        let altitude = converter.zoomLevelToAltitude(
            zoomLevel: tomtomZoomForAltitude,
            latitude: position.latitude,
            tilt: 0.0
        )
        let distanceForward = altitude * cos(tiltAbsRad) * tan(tiltAbsRad) * negativeTiltTargetDistanceScale
        let target = Spherical.computeOffset(origin: position, distance: distanceForward, heading: CameraBearing.toNativeHeading(bearing))
        let adjustedZoom = zoom + negativeTiltZoomOffsetAtMaxTilt * (tiltAbsDeg / 60.0)

        return CameraUpdate(
            position: target.toCoordinate(),
            zoom: TomTomZoomAltitudeConverter.googleZoomToTomTomZoom(
                adjustedZoom,
                latitude: target.latitude
            ),
            tilt: tiltAbsDeg,
            rotation: CameraBearing.toNativeHeading(bearing)
        )
    }
}

public extension CameraProperties {
    /// TomTom `CameraProperties` → MapConductor camera.
    /// `zoom` is TomTom-native, converted to the unified (Google) zoom at the camera latitude.
    ///
    /// - Parameter logicalTiltHint: 直近に要求した論理 tilt（`MapCameraPosition.tilt`）。これが負値の
    ///   とき、シフト済みカメラ状態（前進ターゲット + 正ピッチ）から元の位置・ズーム・負tilt を
    ///   復元する。nil または 0 以上のときは通常変換（android-for-tomtom と同一ロジック）。
    func toMapCameraPosition(
        visibleRegion: MapConductorCore.VisibleRegion? = nil,
        logicalTiltHint: Double? = nil
    ) -> MapCameraPosition {
        let tiltAbsDeg = min(max(abs(tilt), 0.0), 60.0)

        guard let hint = logicalTiltHint, hint < 0.0, tiltAbsDeg > 0.0 else {
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
                bearing: CameraBearing.bearingFromNativeHeading(rotation),
                tilt: tilt,
                visibleRegion: visibleRegion
            )
        }

        // tilt < 0 の復元: 前進させたターゲットとズームオフセットを逆算し、元の位置・ズーム・負tilt を返す。
        let tiltAbsRad = tiltAbsDeg * .pi / 180.0
        let shiftedCenter = GeoPoint(
            latitude: position.latitude,
            longitude: position.longitude,
            altitude: 0
        )
        let googleZoom = TomTomZoomAltitudeConverter.tomtomZoomToGoogleZoom(
            zoom,
            latitude: shiftedCenter.latitude
        )
        let originalGoogleZoom = googleZoom - negativeTiltZoomOffsetAtMaxTilt * (tiltAbsDeg / 60.0)
        let originalTomTomZoom = TomTomZoomAltitudeConverter.googleZoomToTomTomZoom(
            originalGoogleZoom,
            latitude: shiftedCenter.latitude
        )
        let altitude = converter.zoomLevelToAltitude(
            zoomLevel: originalTomTomZoom,
            latitude: shiftedCenter.latitude,
            tilt: 0.0
        )
        let distanceBackward = altitude * cos(tiltAbsRad) * tan(tiltAbsRad) * negativeTiltTargetDistanceScale
        let originalPosition = Spherical.computeOffset(
            origin: shiftedCenter,
            distance: distanceBackward,
            heading: rotation + 180.0
        )

        return MapCameraPosition(
            position: GeoPoint(
                latitude: originalPosition.latitude,
                longitude: originalPosition.longitude,
                altitude: altitude
            ),
            zoom: originalGoogleZoom,
            bearing: CameraBearing.bearingFromNativeHeading(rotation),
            tilt: -tiltAbsDeg,
            visibleRegion: visibleRegion
        )
    }
}
