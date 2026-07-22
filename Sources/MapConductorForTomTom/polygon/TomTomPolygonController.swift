import Combine
import CoreLocation
import MapConductorCore
import TomTomSDKMapDisplay

@MainActor
final class TomTomPolygonController: PolygonController<TomTomActualPolygon, TomTomPolygonRenderer> {
    private var statesById: [String: PolygonState] = [:]
    private var subscriptions: [String: AnyCancellable] = [:]

    init(map: TomTomMap?) {
        super.init(polygonManager: PolygonManager<TomTomActualPolygon>(),
                   renderer: TomTomPolygonRenderer(map: map))
    }

    func syncPolygons(_ polygons: [MapConductorCore.Polygon]) {
        let newIds = Set(polygons.map { $0.id })
        let oldIds = Set(statesById.keys)
        var newStatesById: [String: PolygonState] = [:]
        var shouldSync = oldIds != newIds

        for polygon in polygons {
            let state = polygon.state
            if let existing = statesById[state.id], existing !== state {
                subscriptions[state.id]?.cancel()
                subscriptions.removeValue(forKey: state.id)
                shouldSync = true
            }
            newStatesById[state.id] = state
            if !polygonManager.hasEntity(state.id) { shouldSync = true }
        }
        statesById = newStatesById
        for id in oldIds.subtracting(newIds) {
            subscriptions[id]?.cancel()
            subscriptions.removeValue(forKey: id)
        }
        if shouldSync {
            Task { [weak self] in await self?.add(data: polygons.map { $0.state }) }
        }
        for polygon in polygons { subscribe(polygon.state) }
    }

    func dispatchClick(forTag tag: String?, at coordinate: CLLocationCoordinate2D) {
        guard let tag, let entity = polygonManager.getEntity(tag) else { return }
        dispatchClick(event: PolygonEvent(
            state: entity.state,
            clicked: GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        ))
    }

    private func subscribe(_ state: PolygonState) {
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
