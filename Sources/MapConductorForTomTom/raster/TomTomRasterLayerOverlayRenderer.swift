import MapConductorCore

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

    private func orderedSpecs() -> [TomTomRasterSpec] {
        specs.values.sorted {
            if $0.zIndex == $1.zIndex { return $0.id < $1.id }
            return $0.zIndex < $1.zIndex
        }
    }

    private func notifyLayersChanged() {
        onLayersChanged?(orderedSpecs())
    }
}
