import CoreLocation
import MapConductorCore
import TomTomSDKMapDisplay
import XCTest

@testable import MapConductorForTomTom

/// tilt < 0（上向きピッチ）の擬似表現のテスト。
///
/// TomTom は上向きピッチを直接表現できないため、地上ターゲットを bearing 方向へ前進させ
/// abs(tilt) の下向きピッチで描画する（android-for-tomtom `MapCameraPosition.kt` と同一方式）。
/// 読み戻し時は直近の論理 tilt をヒントに元の位置・ズーム・負tilt を復元する。
final class NegativeTiltCameraTests: XCTestCase {
    private let tokyo = GeoPoint(latitude: 35.6812, longitude: 139.7671, altitude: 0)

    /// `CameraUpdate` から TomTom がカメラ状態として返す `CameraProperties` を組み立てる。
    private func properties(from update: CameraUpdate) -> CameraProperties {
        CameraProperties(
            position: update.position ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
            zoom: update.zoom ?? 0,
            tilt: update.tilt ?? 0,
            rotation: update.rotation ?? 0,
            positionMarkerVerticalOffset: 0,
            scale: 1,
            fieldOfView: 60
        )
    }

    func testNonNegativeTiltIsPassedThroughUnchanged() {
        let camera = MapCameraPosition(position: tokyo, zoom: 14, bearing: 30, tilt: 45)
        let update = camera.toCameraUpdate()

        XCTAssertEqual(update.tilt ?? 0, 45, accuracy: 1e-9)
        XCTAssertEqual(update.rotation ?? 0, 30, accuracy: 1e-9)
        // ターゲットは前進しない
        XCTAssertEqual(update.position?.latitude ?? 0, tokyo.latitude, accuracy: 1e-9)
        XCTAssertEqual(update.position?.longitude ?? 0, tokyo.longitude, accuracy: 1e-9)
    }

    func testNegativeTiltShiftsTargetForwardAndSendsPositivePitch() {
        let camera = MapCameraPosition(position: tokyo, zoom: 14, bearing: 0, tilt: -45)
        let update = camera.toCameraUpdate()

        // SDK へは正のピッチを渡す（負値は表現できない）
        XCTAssertEqual(update.tilt ?? 0, 45, accuracy: 1e-9)
        // bearing = 0（真北）なので、ターゲットは北へ前進する
        XCTAssertGreaterThan(update.position?.latitude ?? 0, tokyo.latitude)
        XCTAssertEqual(update.position?.longitude ?? 0, tokyo.longitude, accuracy: 1e-6)
    }

    /// 往復（論理 → TomTom → 論理）で tilt / zoom / bearing は厳密に、位置はほぼ元へ戻る。
    ///
    /// 位置が厳密に一致しないのは、前進時は元の緯度で、復元時はシフト後の緯度で
    /// ズームオフセットと高度を計算するため（緯度依存の非対称性）。android-for-tomtom も
    /// 同じ式なので誤差の出方まで揃っている。実用上は数十 m で、tilt が浅いほど小さい。
    func testNegativeTiltRoundTripsThroughCameraProperties() {
        for tilt in [-15.0, -30.0, -45.0, -60.0] {
            for bearing in [0.0, 90.0, 217.0] {
                let label = "tilt=\(tilt) bearing=\(bearing)"
                let camera = MapCameraPosition(position: tokyo, zoom: 14, bearing: bearing, tilt: tilt)
                let restored = properties(from: camera.toCameraUpdate())
                    .toMapCameraPosition(logicalTiltHint: tilt)

                XCTAssertEqual(restored.tilt, tilt, accuracy: 1e-6, label)
                XCTAssertEqual(restored.zoom, 14, accuracy: 1e-6, label)
                XCTAssertEqual(restored.bearing, bearing, accuracy: 1e-6, label)

                let drift = Spherical.computeDistanceBetween(from: tokyo, to: restored.position)
                XCTAssertLessThan(drift, 50.0, "\(label): 復元位置のズレ \(drift)m")
            }
        }
    }

    func testWithoutHintNegativeTiltIsNotRestored() {
        let camera = MapCameraPosition(position: tokyo, zoom: 14, bearing: 0, tilt: -45)
        let restored = properties(from: camera.toCameraUpdate()).toMapCameraPosition()

        // ヒントが無ければシフト済みの状態（正ピッチ・前進したターゲット）のまま読める。
        XCTAssertEqual(restored.tilt, 45, accuracy: 1e-9)
        XCTAssertGreaterThan(restored.position.latitude, tokyo.latitude)
    }

    func testPositiveHintLeavesPositiveTiltUntouched() {
        let camera = MapCameraPosition(position: tokyo, zoom: 14, bearing: 0, tilt: 45)
        let restored = properties(from: camera.toCameraUpdate()).toMapCameraPosition(logicalTiltHint: 45)

        XCTAssertEqual(restored.tilt, 45, accuracy: 1e-9)
        XCTAssertEqual(restored.position.latitude, tokyo.latitude, accuracy: 1e-9)
        XCTAssertEqual(restored.zoom, 14, accuracy: 1e-6)
    }

    /// 負tilt はズームを少しだけ引く（最大 tilt で -0.9）。android-for-tomtom と同じ定数。
    func testNegativeTiltAppliesZoomOffset() {
        let camera = MapCameraPosition(position: tokyo, zoom: 14, bearing: 0, tilt: -60)
        let update = camera.toCameraUpdate()
        let googleZoom = TomTomZoomAltitudeConverter.tomtomZoomToGoogleZoom(
            update.zoom ?? 0,
            latitude: update.position?.latitude ?? 0
        )

        XCTAssertEqual(googleZoom, 14 - 0.9, accuracy: 1e-6)
    }
}
