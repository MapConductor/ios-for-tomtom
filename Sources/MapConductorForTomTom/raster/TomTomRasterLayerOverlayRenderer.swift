@_spi(MapConductorDriver) import MapConductorCore

@MainActor
final class TomTomRasterLayerOverlayRenderer: AbstractRasterLayerOverlayRenderer<TomTomRasterLayer> {
    var onLayersChanged: (([TomTomRasterSpec]) -> Void)?

    private var specs: [String: TomTomRasterSpec] = [:]

    override func createLayer(state: RasterLayerState) async -> TomTomRasterLayer? {
        RasterHeaderRuleSet.warnUnsupported(provider: "TomTom", state: state)
        updateSpec(state)
        return TomTomRasterLayer(id: state.id)
    }

    override func updateLayerProperties(
        layer: TomTomRasterLayer,
        current: RasterLayerEntity<TomTomRasterLayer>,
        prev _: RasterLayerEntity<TomTomRasterLayer>
    ) async -> TomTomRasterLayer? {
        updateSpec(current.state)
        return layer
    }

    override func removeLayer(entity: RasterLayerEntity<TomTomRasterLayer>) async {
        specs.removeValue(forKey: entity.state.id)
    }

    override func onPostProcess() async {
        notifyLayersChanged()
    }

    func allSpecs() -> [TomTomRasterSpec] {
        orderedSpecs()
    }

    func unbind() {
        specs.removeAll()
        onLayersChanged = nil
    }

    private func updateSpec(_ state: RasterLayerState) {
        guard state.visible else {
            specs.removeValue(forKey: state.id)
            return
        }
        specs[state.id] = TomTomRasterSpec(
            id: state.id,
            source: state.source,
            opacity: min(max(state.opacity, 0), 1),
            zIndex: state.zIndex
        )
    }

    /// The raster layers in the style, bottom first. The SDK's own tile layers
    /// (polygon, polyline and marker tiles) take their overlay band
    /// (``OverlayStacking/rasterKey(stateId:zIndex:)``): the app's rasters, then
    /// polygon tiles, then polyline tiles, then marker tiles. TomTom draws its
    /// annotations (native polygons, circles, polylines) above every style layer,
    /// so these only order the layers among themselves.
    private func orderedSpecs() -> [TomTomRasterSpec] {
        specs.values.sorted {
            let a = OverlayStacking.rasterKey(stateId: $0.id, zIndex: $0.zIndex)
            let b = OverlayStacking.rasterKey(stateId: $1.id, zIndex: $1.zIndex)
            if a == b { return $0.id < $1.id }
            return a < b
        }
    }

    private func notifyLayersChanged() {
        onLayersChanged?(orderedSpecs())
    }
}
