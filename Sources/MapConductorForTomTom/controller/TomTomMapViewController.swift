import CoreLocation
import Foundation
import MapConductorCore
import TomTomSDKMapDisplay

final class TomTomMapViewController: MapViewControllerProtocol {
    let holder: AnyMapViewHolder
    let coroutine = CoroutineScope()

    private weak var mapView: MapView?
    private weak var map: TomTomMap?

    private var cameraMoveStartListener: OnCameraMoveHandler?
    private var cameraMoveListener: OnCameraMoveHandler?
    private var cameraMoveEndListener: OnCameraMoveHandler?
    private var mapClickListener: OnMapEventHandler?
    private var mapLongClickListener: OnMapEventHandler?
    private var mapInitializedListener: OnMapInitializedHandler?

    private let tomtomHolder: TomTomMapViewHolder

    init(mapView: MapView, map: TomTomMap) {
        self.mapView = mapView
        self.map = map
        let holder = TomTomMapViewHolder(mapView: mapView, map: map)
        self.tomtomHolder = holder
        self.holder = AnyMapViewHolder(holder)
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
    func notifyMapClick(_ point: GeoPoint) { mapClickListener?(point) }
    func notifyMapLongClick(_ point: GeoPoint) { mapLongClickListener?(point) }
    func notifyMapInitialized() { mapInitializedListener?(.MapCreated) }
}
