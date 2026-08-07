import MapConductorCore

final class TomTomRasterLayer {
    let id: String

    init(id: String) {
        self.id = id
    }
}

struct TomTomRasterSpec {
    let id: String
    let source: RasterLayerSource
    let opacity: Double
    let zIndex: Int
}
