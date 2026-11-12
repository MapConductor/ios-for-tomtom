import CoreLocation
import Foundation
@_spi(MapConductorDriver) import MapConductorCore
import TomTomSDKMapDisplay

final class TomTomMapViewController: MapViewControllerProtocol {
    let holder: AnyMapViewHolder
    let typedHolder: TomTomMapViewHolder
    let coroutine = CoroutineScope()

    /// この地図に紐づくオーバーレイコントローラの登録簿。
    /// 拡張モジュール（ヒートマップ、マーカークラスタリング等）がここに登録して
    /// カメラ変更を受け取る。`MapViewControllerProtocol` の要件。
    let overlayControllers = OverlayControllerRegistry()

    private weak var mapView: MapView?
    private weak var map: TomTomMap?

    private var cameraMoveStartListener: OnCameraMoveHandler?
    private var cameraMoveListener: OnCameraMoveHandler?
    private var cameraMoveEndListener: OnCameraMoveHandler?

    /// TomTom はネイティブのカメラ範囲制限 API を持たないため、android-for-tomtom と同じく
    /// カメラ停止（steady）時に矩形内へクランプして再適用する方式で制限する。
    private let cameraRestrictionClamp = CameraRestrictionClamp()
    private var mapClickListener: OnMapEventHandler?
    private var mapLongClickListener: OnMapEventHandler?
    private var mapInitializedListener: OnMapInitializedHandler?

    /// 直近に要求した論理 tilt。tilt < 0 の擬似表現は SDK 側では正ピッチになるため、
    /// カメラ状態の読み戻し時に元の負tilt を復元するヒントとして保持する
    /// （android-for-tomtom の `lastLogicalCameraPosition` / MapLibre と同方針）。
    private(set) var lastLogicalTilt: Double?
    /// 直近の移動で要求されたパディング。TomTom のカメラには使えるパディングが無いので、中心を
    /// ずらして再現し（``CameraPaddingEmulation``）、読み戻しで逆にずらすときに使う。
    private(set) var lastPaddings: MapPaddingsProtocol?

    /// 初期カメラ（MapOptions 経由で適用され `moveCamera` を通らない）の論理 tilt を記録する。
    func seedLogicalTilt(_ tilt: Double) {
        lastLogicalTilt = tilt
    }

    init(mapView: MapView, map: TomTomMap) {
        self.mapView = mapView
        self.map = map
        let typedHolder = TomTomMapViewHolder(mapView: mapView, map: map)
        self.typedHolder = typedHolder
        self.holder = AnyMapViewHolder(typedHolder)
    }

    /// ``clearOverlays()`` の中身。オーバーレイのコントローラはホストが持っているので、
    /// ホストが生成時に設定する（android-sdk と同じく、各コントローラの `clear()` を呼ぶ）。
    var clearOverlaysHandler: (@MainActor () async -> Void)?

    func clearOverlays() async {
        await clearOverlaysHandler?()
    }

    func setCameraMoveStartListener(listener: OnCameraMoveHandler?) { cameraMoveStartListener = listener }
    func setCameraMoveListener(listener: OnCameraMoveHandler?) { cameraMoveListener = listener }
    func setCameraMoveEndListener(listener: OnCameraMoveHandler?) { cameraMoveEndListener = listener }
    func setMapClickListener(listener: OnMapEventHandler?) { mapClickListener = listener }
    func setMapLongClickListener(listener: OnMapEventHandler?) { mapLongClickListener = listener }
    func setMapInitializedListener(listener: OnMapInitializedHandler?) { mapInitializedListener = listener }

    func moveCamera(position requested: MapCameraPosition) {
        lastPaddings = requested.paddings
        let position = paddingApplied(requested)
        lastLogicalTilt = position.tilt
        map?.moveCamera(position.toCameraUpdate())
    }

    func animateCamera(position requested: MapCameraPosition, duration: Long) {
        lastPaddings = requested.paddings
        let position = paddingApplied(requested)
        lastLogicalTilt = position.tilt
        map?.applyCamera(
            position.toCameraUpdate(),
            animationDuration: TimeInterval(duration) / 1000.0,
            completion: nil
        )
    }

    /// TomTom へ渡すカメラ。パディングの分だけ中心をずらす。
    private func paddingApplied(_ position: MapCameraPosition) -> MapCameraPosition {
        CameraPaddingEmulation.applied(
            to: position,
            fov: tomTomVerticalFieldOfView,
            viewportSize: mapView?.bounds.size ?? .zero
        )
    }

    /// TomTom から読み戻したカメラ（画面中心）を、ターゲット・パディング・視野角を持つカメラへ戻す。
    func reportedCamera(_ camera: MapCameraPosition) -> MapCameraPosition {
        CameraPaddingEmulation.restored(
            camera,
            paddings: lastPaddings,
            fov: tomTomVerticalFieldOfView,
            viewportSize: mapView?.bounds.size ?? .zero
        )
    }

    func fitBounds(bounds: GeoRectBounds, padding: Int) {
        guard let sw = bounds.southWest, let ne = bounds.northEast else { return }
        let coordinates = [
            CLLocationCoordinate2D(latitude: sw.latitude, longitude: sw.longitude),
            CLLocationCoordinate2D(latitude: ne.latitude, longitude: ne.longitude),
        ]
        map?.moveCamera(CameraUpdate(fitToCoordinates: coordinates, padding: UInt(max(0, padding))))
    }

    // MARK: - Notifications (called from the coordinator's MapDelegate)

    func notifyCameraMoveStart(_ camera: MapCameraPosition) { cameraMoveStartListener?(camera) }
    func notifyCameraMove(_ camera: MapCameraPosition) { cameraMoveListener?(camera) }
    func notifyCameraMoveEnd(_ camera: MapCameraPosition) {
        // 登録済みオーバーレイ（拡張モジュール含む）へ伝播する。
        overlayControllers.dispatchCameraChanged(camera)
        cameraMoveEndListener?(camera)
    }

    func setCameraRestriction(_ restriction: CameraRestriction?) {
        cameraRestrictionClamp.set(restriction)
    }

    /// カメラ停止時に制限違反を補正する。補正したら `true`（通常のカメラ停止処理はスキップし、
    /// 再適用後に再発火する steady で通常フローへ進む）。android-for-tomtom と同一仕様。
    func applyCameraRestrictionCorrectionIfNeeded(_ current: MapCameraPosition) -> Bool {
        guard let corrected = cameraRestrictionClamp.correction(for: current) else { return false }
        moveCamera(position: corrected)
        return true
    }
    func notifyMapClick(_ point: GeoPoint) { mapClickListener?(point) }
    func notifyMapLongClick(_ point: GeoPoint) { mapLongClickListener?(point) }
    func notifyMapInitialized() { mapInitializedListener?(.MapCreated) }
}
