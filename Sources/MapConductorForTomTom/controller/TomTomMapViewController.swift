import CoreLocation
import Foundation
import MapConductorCore
import TomTomSDKMapDisplay

final class TomTomMapViewController: MapViewControllerProtocol {
    let holder: AnyMapViewHolder
    let typedHolder: TomTomMapViewHolder
    let coroutine = CoroutineScope()

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

    init(mapView: MapView, map: TomTomMap) {
        self.mapView = mapView
        self.map = map
        let typedHolder = TomTomMapViewHolder(mapView: mapView, map: map)
        self.typedHolder = typedHolder
        self.holder = AnyMapViewHolder(typedHolder)
    }

    func clearOverlays() async {
        map?.removeAnnotations()
    }

    func setCameraMoveStartListener(listener: OnCameraMoveHandler?) { cameraMoveStartListener = listener }
    func setCameraMoveListener(listener: OnCameraMoveHandler?) { cameraMoveListener = listener }
    func setCameraMoveEndListener(listener: OnCameraMoveHandler?) { cameraMoveEndListener = listener }
    func setMapClickListener(listener: OnMapEventHandler?) { mapClickListener = listener }
    func setMapLongClickListener(listener: OnMapEventHandler?) { mapLongClickListener = listener }
    func setMapInitializedListener(listener: OnMapInitializedHandler?) { mapInitializedListener = listener }

    func moveCamera(position: MapCameraPosition) {
        map?.moveCamera(position.toCameraUpdate())
    }

    func animateCamera(position: MapCameraPosition, duration: Long) {
        map?.applyCamera(
            position.toCameraUpdate(),
            animationDuration: TimeInterval(duration) / 1000.0,
            completion: nil
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
    func notifyCameraMoveEnd(_ camera: MapCameraPosition) { cameraMoveEndListener?(camera) }

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
