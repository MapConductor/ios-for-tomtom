import Combine
import CoreLocation
import MapConductorCore
import TomTomSDKMapDisplay

@MainActor
final class TomTomGroundImageController:
    GroundImageController<TomTomActualGroundImage, TomTomGroundImageOverlayRenderer>
{
    private var statesById: [String: GroundImageState] = [:]
    private var subscriptions: [String: AnyCancellable] = [:]

    init(map: TomTomMap?) {
        super.init(
            groundImageManager: GroundImageManager<TomTomActualGroundImage>(),
            renderer: TomTomGroundImageOverlayRenderer(map: map)
        )
    }

    func syncGroundImages(_ groundImages: [GroundImage]) {
        let newIds = Set(groundImages.map(\.id))
        let oldIds = Set(statesById.keys)
        var nextStates: [String: GroundImageState] = [:]
        var shouldSync = oldIds != newIds

        for groundImage in groundImages {
            let state = groundImage.state
            if let existing = statesById[state.id], existing !== state {
                subscriptions[state.id]?.cancel()
                subscriptions.removeValue(forKey: state.id)
                shouldSync = true
            }
            nextStates[state.id] = state
            if !groundImageManager.hasEntity(state.id) { shouldSync = true }
            if let entity = groundImageManager.getEntity(state.id), entity.fingerPrint != state.fingerPrint() {
                shouldSync = true
            }
        }

        statesById = nextStates
        for id in oldIds.subtracting(newIds) {
            subscriptions[id]?.cancel()
            subscriptions.removeValue(forKey: id)
        }
        if shouldSync {
            Task { [weak self] in
                await self?.add(data: groundImages.map { $0.state })
            }
        }
        for groundImage in groundImages { subscribe(groundImage.state) }
    }

    func dispatchClick(forTag tag: String?, at coordinate: CLLocationCoordinate2D) -> Bool {
        guard let id = groundImageId(from: tag), let entity = groundImageManager.getEntity(id) else {
            return false
        }
        dispatchClick(
            event: GroundImageEvent(
                state: entity.state,
                clicked: GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
            )
        )
        return true
    }

    private func subscribe(_ state: GroundImageState) {
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
        renderer.unbind()
        destroy()
    }
}
