import Combine
import CoreLocation
import MapConductorCore
import TomTomSDKMapDisplay

@MainActor
final class TomTomCircleController: CircleController<TomTomActualCircle, TomTomCircleRenderer> {
    private var statesById: [String: CircleState] = [:]
    private var subscriptions: [String: AnyCancellable] = [:]

    init(map: TomTomMap?) {
        super.init(circleManager: CircleManager<TomTomActualCircle>(),
                   renderer: TomTomCircleRenderer(map: map))
    }

    func syncCircles(_ circles: [MapConductorCore.Circle]) {
        let newIds = Set(circles.map { $0.id })
        let oldIds = Set(statesById.keys)
        var newStatesById: [String: CircleState] = [:]
        var shouldSync = oldIds != newIds

        for circle in circles {
            let state = circle.state
            if let existing = statesById[state.id], existing !== state {
                subscriptions[state.id]?.cancel()
                subscriptions.removeValue(forKey: state.id)
                shouldSync = true
            }
            newStatesById[state.id] = state
            if !circleManager.hasEntity(state.id) { shouldSync = true }
        }
        statesById = newStatesById
        for id in oldIds.subtracting(newIds) {
            subscriptions[id]?.cancel()
            subscriptions.removeValue(forKey: id)
        }
        if shouldSync {
            Task { [weak self] in await self?.add(data: circles.map { $0.state }) }
        }
        for circle in circles { subscribe(circle.state) }
    }

    func dispatchClick(forTag tag: String?, at coordinate: CLLocationCoordinate2D) {
        guard let tag, let entity = circleManager.getEntity(tag) else { return }
        dispatchClick(event: CircleEvent(
            state: entity.state,
            clicked: GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        ))
    }

    private func subscribe(_ state: CircleState) {
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
