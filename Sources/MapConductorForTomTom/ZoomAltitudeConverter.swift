import Foundation
import MapConductorCore

/// 統一ズーム（Google Maps 基準・256px タイル）⇄ 高度の変換。
///
/// TomTom のズームはグラウンドスケール基準（画面上の meter/pixel が緯度によらず一定）
/// なので、Web Mercator 基準との差が緯度に依存する。オフセットは
/// `1.76 + log2(cos φ)`。1.76 は実測較正値（Camera Sync でオアフ島 ≈ 1.66、東京 ≈ 1.46）。
/// 表示スケールとビューポート寸法は意図的に式へ入れていない。Android のクロスデバイス
/// 較正で、両 SDK とも論理ビューポート寸法に追従済みだと分かっているため。
///
/// 換算式はコアの ``GroundScaleZoomAltitudeConverter`` にある。
public final class TomTomZoomAltitudeConverter: GroundScaleZoomAltitudeConverter {
    /// Equatorial offset (`googleZoom - tomtomZoom`).
    public static let tomtomToGoogleZoomBaseOffset: Double = 1.76

    public init(zoom0Altitude: Double = AbstractZoomAltitudeConverter.defaultZoom0Altitude) {
        super.init(zoom0Altitude: zoom0Altitude, baseZoomOffset: Self.tomtomToGoogleZoomBaseOffset)
    }

    public static func zoomOffset(at latitude: Double) -> Double {
        let clampedLatitude = max(-85.0, min(latitude, 85.0))
        let cosine = max(abs(cos(clampedLatitude * .pi / 180.0)), AbstractZoomAltitudeConverter.minCosLat)
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
}
