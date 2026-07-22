import Combine
import CoreLocation
import MapConductorCore
import TomTomSDKMapDisplay

@MainActor
final class TomTomPolylineController: PolylineController<TomTomActualPolyline, TomTomPolylineRenderer> {
    private var statesById: [String: PolylineState] = [:]
    private var subscriptions: [String: AnyCancellable] = [:]

    init(map: TomTomMap?) {
        super.init(polylineManager: PolylineManager<TomTomActualPolyline>(),
                   renderer: TomTomPolylineRenderer(map: map))
    }

    func syncPolylines(_ polylines: [MapConductorCore.Polyline]) {
        let newIds = Set(polylines.map { $0.id })
        let oldIds = Set(statesById.keys)
        var newStatesById: [String: PolylineState] = [:]
        var shouldSync = oldIds != newIds

        for polyline in polylines {
            let state = polyline.state
            if let existing = statesById[state.id], existing !== state {
                subscriptions[state.id]?.cancel()
                subscriptions.removeValue(forKey: state.id)
                shouldSync = true
            }
            newStatesById[state.id] = state
            if !polylineManager.hasEntity(state.id) { shouldSync = true }
        }
        statesById = newStatesById
        for id in oldIds.subtracting(newIds) {
            subscriptions[id]?.cancel()
            subscriptions.removeValue(forKey: id)
        }
        if shouldSync {
            Task { [weak self] in await self?.add(data: polylines.map { $0.state }) }
        }
        for polyline in polylines { subscribe(polyline.state) }
    }

    /// Dispatch a click for the tapped native line (matched by tag == state.id).
    func dispatchClick(forTag tag: String?, at coordinate: CLLocationCoordinate2D) {
        guard let tag, let entity = polylineManager.getEntity(tag) else { return }
        dispatchClick(event: PolylineEvent(
            state: entity.state,
            clicked: GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        ))
    }

    private func subscribe(_ state: PolylineState) {
        guard subscriptions[state.id] == nil else { return }
        subscriptions[state.id] = state.asFlow()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.statesById[state.id] != nil else { return }
                Task { [weak self] in await self?.update(state: state) }
            }
    }

    func unbind() {
        subscriptions.values.forEach { $0.cancel() }
        subscriptions.removeAll()
        statesById.removeAll()
        destroy()
    }
}
