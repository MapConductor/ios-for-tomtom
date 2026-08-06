import Combine
import CoreGraphics
import MapConductorCore
import TomTomSDKMapDisplay
import UIKit

/// Core + markers scope: a straightforward native-marker controller (no tile rendering).
@MainActor
final class TomTomMarkerController: AbstractMarkerController<TomTomActualMarker, TomTomMarkerRenderer> {
    private weak var map: TomTomMap?

    private var markerStatesById: [String: MarkerState] = [:]
    private var markerSubscriptions: [String: AnyCancellable] = [:]

    init(map: TomTomMap?) {
        self.map = map
        let markerManager = MarkerManager<TomTomActualMarker>.defaultManager()
        let renderer = TomTomMarkerRenderer(map: map)
        super.init(markerManager: markerManager, renderer: renderer)
    }

    /// Screen-space hit-test used by the custom drag gesture.
    ///
    /// 判定は他プロバイダと同じ ``MarkerHitTest``（アイコン矩形 + `tapTolerance`）。以前は
    /// アイコンの大きさを見ない固定半径で、さらに `tapTolerance`（ポイント）へ
    /// `UIScreen.main.scale` を掛けていたため、`pointForCoordinate` が返すポイント座標に対して
    /// 許容量が 2〜3 倍に膨らんでいた。Android が dp × density としているのは、あちらの画面座標が
    /// px だから。iOS のポイントは既に dp 相当なので倍率は掛けない。
    override func find(position: GeoPointProtocol) -> MarkerEntity<TomTomActualMarker>? {
        guard let nearest = markerManager.findNearest(position: position) else { return nil }
        // The base `find` is nonisolated; our drag hit-test always runs on the main thread
        // (invoked from the gesture handler), so assume main-actor isolation to touch `map`.
        return MainActor.assumeIsolated {
            guard let map,
                  let touchPoint = map.pointForCoordinate(coordinate: position.toCoordinate()),
                  let markerPoint = map.pointForCoordinate(coordinate: nearest.state.position.toCoordinate())
            else {
                return nil
            }
            return MarkerHitTest.hitsIcon(
                touchScreen: touchPoint,
                markerScreen: markerPoint,
                state: nearest.state
            ) ? nearest : nil
        }
    }

    func getMarkerState(for id: String) -> MarkerState? {
        markerManager.getEntity(id)?.state
    }

    func syncMarkers(_ markers: [MapConductorCore.Marker]) {
        let newIds = Set(markers.map { $0.id })
        let oldIds = Set(markerStatesById.keys)

        var newStatesById: [String: MarkerState] = [:]
        var shouldSyncList = oldIds != newIds

        for marker in markers {
            let state = marker.state
            if let existing = markerStatesById[state.id], existing !== state {
                markerSubscriptions[state.id]?.cancel()
                markerSubscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            newStatesById[state.id] = state
            if !markerManager.hasEntity(state.id) { shouldSyncList = true }
        }

        markerStatesById = newStatesById

        for id in oldIds.subtracting(newIds) {
            markerSubscriptions[id]?.cancel()
            markerSubscriptions.removeValue(forKey: id)
        }

        if shouldSyncList {
            Task { [weak self] in
                await self?.add(data: markers.map { $0.state })
            }
        }

        for marker in markers {
            subscribeToMarker(marker.state)
        }
    }

    private func subscribeToMarker(_ state: MarkerState) {
        guard markerSubscriptions[state.id] == nil else { return }
        markerSubscriptions[state.id] = state.asFlow()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.markerStatesById[state.id] != nil else { return }
                Task { [weak self] in
                    await self?.update(state: state)
                }
            }
    }

    func unbind() {
        markerSubscriptions.values.forEach { $0.cancel() }
        markerSubscriptions.removeAll()
        markerStatesById.removeAll()
        renderer.unbind()
        map = nil
        destroy()
    }
}
