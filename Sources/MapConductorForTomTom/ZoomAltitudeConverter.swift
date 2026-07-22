import Foundation
import MapConductorCore

/// Converts between TomTom native zoom and MapConductor's Google-equivalent unified zoom.
public final class TomTomZoomAltitudeConverter: ZoomAltitudeConverterProtocol {
    public let zoom0Altitude: Double

    /// Equatorial offset (`googleZoom - tomtomZoom`).
    ///
    /// TomTom uses ground scale while Google Maps uses Web Mercator scale. Their relationship
    /// therefore varies by latitude: `offset(latitude) = base + log2(cos(latitude))`.
    /// Camera Sync calibration gives approximately 1.66 on Oahu and 1.46 in Tokyo.
    /// Viewport dimensions and display scale are intentionally not part of this conversion; the
    /// Android cross-device calibration showed both SDKs already track logical viewport size.
    public static let tomtomToGoogleZoomBaseOffset: Double = 1.76

    private let zoomFactor: Double = 2.0
    private let minZoomLevel: Double = 0.0
    private let maxZoomLevel: Double = 22.0
    private let minAltitude: Double = 100.0
    private let maxAltitude: Double = 50_000_000.0
    private let minCosLat: Double = 0.01
    private let minCosTilt: Double = 0.05

    public init(zoom0Altitude: Double = 171_319_879.0) {
        self.zoom0Altitude = zoom0Altitude
    }

    public static func zoomOffset(at latitude: Double) -> Double {
        let clampedLatitude = max(-85.0, min(latitude, 85.0))
        let cosine = max(abs(cos(clampedLatitude * .pi / 180.0)), 0.01)
        return tomtomToGoogleZoomBaseOffset + log2(cosine)
    }

    public static func tomtomZoomToGoogleZoom(
        _ tomtomZoom: Double,
        latitude: Double = 0.0
    ) -> Double {
        min(max(tomtomZoom + zoomOffset(at: latitude), 0.0), 22.0)
    }

    public static func googleZoomToTomTomZoom(
        _ googleZoom: Double,
        latitude: Double = 0.0
    ) -> Double {
        min(max(googleZoom - zoomOffset(at: latitude), 0.0), 22.0)
    }

    /// Input `zoomLevel` is TomTom-native zoom; it is converted to Google-equivalent first.
    public func zoomLevelToAltitude(zoomLevel: Double, latitude: Double, tilt: Double) -> Double {
        let googleZoom = Self.tomtomZoomToGoogleZoom(zoomLevel, latitude: latitude)
        let clampedZoom = max(minZoomLevel, min(googleZoom, maxZoomLevel))
        let clampedLat = max(-85.0, min(latitude, 85.0))
        let cosLat = max(abs(cos(clampedLat * .pi / 180.0)), minCosLat)
        let clampedTilt = max(0.0, min(tilt, 90.0))
        let cosTilt = max(cos(clampedTilt * .pi / 180.0), minCosTilt)

        let distance = (zoom0Altitude * cosLat) / pow(zoomFactor, clampedZoom)
        let altitude = distance * cosTilt
        return max(minAltitude, min(altitude, maxAltitude))
    }

    /// Returns TomTom-native zoom.
    public func altitudeToZoomLevel(altitude: Double, latitude: Double, tilt: Double) -> Double {
        let clampedAltitude = max(minAltitude, min(altitude, maxAltitude))
        let clampedLat = max(-85.0, min(latitude, 85.0))
        let cosLat = max(abs(cos(clampedLat * .pi / 180.0)), minCosLat)
        let clampedTilt = max(0.0, min(tilt, 90.0))
        let cosTilt = max(cos(clampedTilt * .pi / 180.0), minCosTilt)

        let distance = clampedAltitude / cosTilt
        let googleZoom = log2((zoom0Altitude * cosLat) / distance)
        return Self.googleZoomToTomTomZoom(googleZoom, latitude: latitude)
    }
}
