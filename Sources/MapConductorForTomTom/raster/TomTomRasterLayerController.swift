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

    func updateDesign(_ design: TomTomMapDesign) {
        fallbackDesign = design
        if !isUsingComposedStyle {
            map?.styleContainer = design.styleContainer
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
        renderer.unbind()
        map = nil
        destroy()
    }
}
