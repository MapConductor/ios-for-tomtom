import Foundation
import MapConductorCore

/// 統一ズーム（Google Maps 基準・256px タイル）⇄ 高度の変換。
///
/// TomTom のズームはグラウンドスケール基準（画面上の meter/pixel が緯度によらず一定）
/// なので、Web Mercator 基準との差が緯度に依存する。オフセットは
/// `1.735 + log2(cos φ)`。1.735 は実測較正値（オアフ島 ≈ 1.63、東京 ≈ 1.435）。
///
/// 較正は iPad Pro 11"（TomTom Orbis Maps SDK 0.74.0）で、同じ統一ズーム・同じ地図サイズの
/// Google Maps と画面中心付近の縮尺（`coordinateForPoint` で取った ±150pt の距離）を突き合わせて行った。
/// 以前の 1.76 では TomTom が緯度 0〜65°、zoom 9〜19 のどこでも 0.025 段だけ広く写っていた。
/// Android（TB520FU、TomTom Maps SDK 2.7.2）でも同じ 0.025 段のずれで、同じ値に揃えてある。
/// 表示スケールとビューポート寸法は意図的に式へ入れていない。Android のクロスデバイス
/// 較正で、両 SDK とも論理ビューポート寸法に追従済みだと分かっているため。
///
/// 換算式はコアの ``GroundScaleZoomAltitudeConverter`` にある。
public final class TomTomZoomAltitudeConverter: GroundScaleZoomAltitudeConverter {
    /// Equatorial offset (`googleZoom - tomtomZoom`).
    public static let tomtomToGoogleZoomBaseOffset: Double = 1.735

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
