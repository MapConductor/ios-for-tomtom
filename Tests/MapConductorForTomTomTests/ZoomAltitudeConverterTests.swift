import XCTest
@testable import MapConductorForTomTom

final class ZoomAltitudeConverterTests: XCTestCase {
    func testTokyoOffsetMatchesCameraSyncCalibration() {
        XCTAssertEqual(
            TomTomZoomAltitudeConverter.zoomOffset(at: 35.6812),
            1.46,
            accuracy: 0.01
        )
    }

    func testOahuOffsetMatchesCameraSyncCalibration() {
        XCTAssertEqual(
            TomTomZoomAltitudeConverter.zoomOffset(at: 21.4389),
            1.66,
            accuracy: 0.01
        )
    }

    func testZoomConversionRoundTrips() {
        let googleZoom = 12.0
        let latitude = 35.6812
        let tomtomZoom = TomTomZoomAltitudeConverter.googleZoomToTomTomZoom(
            googleZoom,
            latitude: latitude
        )
        let convertedBack = TomTomZoomAltitudeConverter.tomtomZoomToGoogleZoom(
            tomtomZoom,
            latitude: latitude
        )

        XCTAssertEqual(convertedBack, googleZoom, accuracy: 1e-12)
    }
}
