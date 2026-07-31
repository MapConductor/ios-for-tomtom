import Combine
import Foundation
import MapConductorCore
import TomTomSDKMapDisplay

@MainActor
final class TomTomRasterLayerController:
    RasterLayerController<TomTomRasterLayer, TomTomRasterLayerOverlayRenderer>
{
    private weak var map: TomTomMap?
    private let apiKey: String
    private var fallbackDesign: TomTomMapDesign
    private var statesById: [String: RasterLayerState] = [:]
    private var subscriptions: [String: AnyCancellable] = [:]
    private var styleTask: Task<Void, Never>?
    private var outputToggle = 0
    private let outputPrefix = UUID().uuidString

    var isUsingComposedStyle: Bool {
        !renderer.allSpecs().isEmpty
    }

    init(map: TomTomMap?, apiKey: String, fallbackDesign: TomTomMapDesign) {
        self.map = map
        self.apiKey = apiKey
        self.fallbackDesign = fallbackDesign
        let renderer = TomTomRasterLayerOverlayRenderer()
        super.init(
            rasterLayerManager: RasterLayerManager<TomTomRasterLayer>(),
            renderer: renderer
        )
        renderer.onLayersChanged = { [weak self] specs in
            self?.scheduleStyleUpdate(specs: specs)
        }
    }

    func syncRasterLayers(_ layers: [RasterLayer]) {
        let newIds = Set(layers.map(\.id))
        let oldIds = Set(statesById.keys)
        var nextStates: [String: RasterLayerState] = [:]
        var shouldSync = oldIds != newIds

        for layer in layers {
            let state = layer.state
            if let existing = statesById[state.id], existing !== state {
                subscriptions[state.id]?.cancel()
                subscriptions.removeValue(forKey: state.id)
                shouldSync = true
            }
            nextStates[state.id] = state
            if !rasterLayerManager.hasEntity(state.id) { shouldSync = true }
            if let entity = rasterLayerManager.getEntity(state.id), entity.fingerPrint != state.fingerPrint() {
                shouldSync = true
            }
        }

        statesById = nextStates
        for id in oldIds.subtracting(newIds) {
            subscriptions[id]?.cancel()
            subscriptions.removeValue(forKey: id)
        }
        if shouldSync {
            Task { [weak self] in await self?.add(data: layers.map { $0.state }) }
        }
        for layer in layers { subscribe(layer.state) }
    }

    func updateDesign(_ design: TomTomMapDesign) {
        fallbackDesign = design
        if !isUsingComposedStyle {
            map?.styleContainer = design.styleContainer
        }
    }

    private func subscribe(_ state: RasterLayerState) {
        guard subscriptions[state.id] == nil else { return }
        subscriptions[state.id] = state.asFlow()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.statesById[state.id] != nil else { return }
                Task { [weak self] in await self?.update(state: state) }
            }
    }

    private func scheduleStyleUpdate(specs: [TomTomRasterSpec]) {
        styleTask?.cancel()
        styleTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await self?.applyStyle(specs: specs)
            } catch {
                // A newer layer update superseded this one.
            }
        }
    }

    private func applyStyle(specs: [TomTomRasterSpec]) async {
        guard let map else { return }
        guard !specs.isEmpty else {
            map.styleContainer = fallbackDesign.styleContainer
            return
        }
        guard !apiKey.isEmpty else {
            NSLog("[MapConductor] TomTom RasterLayer requires a TomTom API key.")
            return
        }

        outputToggle ^= 1
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mapconductor_tomtom_style_\(outputPrefix)_\(outputToggle).json")
        do {
            let style = try await TomTomStyleComposer.shared.compose(
                apiKey: apiKey,
                layers: specs,
                outputURL: outputURL
            )
            guard !Task.isCancelled else { return }
            map.styleContainer = style
        } catch {
            NSLog("[MapConductor] Failed to compose TomTom raster style: %@", String(describing: error))
        }
    }

    func unbind() {
        styleTask?.cancel()
        styleTask = nil
        subscriptions.values.forEach { $0.cancel() }
        subscriptions.removeAll()
        statesById.removeAll()
        renderer.unbind()
        map = nil
        destroy()
    }
}
