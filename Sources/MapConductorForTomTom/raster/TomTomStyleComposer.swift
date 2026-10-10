import Foundation
import MapConductorCore
import TomTomSDKMapDisplay

actor TomTomStyleComposer {
    static let shared = TomTomStyleComposer()

    private var cachedBaseStyles: [String: [String: Any]] = [:]

    /// - Parameter withoutBasemap: for ``TomTomMapDesign/None``. The browsing
    /// style stays the skeleton -- this SDK falls back to its default style
    /// when handed one without its own layers (measured: a bare background
    /// style put the default map back at world scale) -- but every layer of
    /// it except the background is hidden, so no TomTom tile is fetched and
    /// the raster layers sit on a background colour.
    func compose(
        apiKey: String,
        layers: [TomTomRasterSpec],
        outputURL: URL,
        withoutBasemap: Bool = false
    ) async throws -> StyleContainer {
        var root = try await baseStyle(apiKey: apiKey, nextTo: outputURL)
        var sources = root["sources"] as? [String: Any] ?? [:]
        var styleLayers = root["layers"] as? [[String: Any]] ?? []

        if withoutBasemap {
            styleLayers = styleLayers.map { layer in
                var layer = layer
                if layer["type"] as? String == "background" {
                    layer["paint"] = ["background-color": BlankMapStyle.backgroundColor]
                } else {
                    var layout = layer["layout"] as? [String: Any] ?? [:]
                    layout["visibility"] = "none"
                    layer["layout"] = layout
                }
                return layer
            }
        } else {
            sources["mc-base-raster"] = rasterTileSource(
                template: baseRasterTemplate(apiKey: apiKey),
                tileSize: 256,
                minZoom: nil,
                maxZoom: nil,
                scheme: .XYZ
            )
            let baseLayer = rasterLayer(id: "mc-base-raster-layer", source: "mc-base-raster", opacity: 1)
            let baseIndex = styleLayers.first?["type"] as? String == "background" ? 1 : 0
            styleLayers.insert(baseLayer, at: min(baseIndex, styleLayers.count))
        }

        for (index, spec) in layers.enumerated() {
            let sourceId = "mc-raster-src-\(index)"
            sources[sourceId] = rasterSource(spec.source)
            styleLayers.append(
                rasterLayer(
                    id: "mc-raster-layer-\(index)-\(styleIdentifier(spec.id))",
                    source: sourceId,
                    opacity: spec.opacity
                )
            )
        }

        root["sources"] = sources
        root["layers"] = styleLayers
        let data = try JSONSerialization.data(withJSONObject: root, options: [])
        try data.write(to: outputURL, options: .atomic)
        return StyleContainer(mainStyle: .custom(style: outputURL))
    }

    /// The browsing style's skeleton.
    ///
    /// The SDK will not take a style that has none of its own layers (it
    /// reverts to its default), so every composed style is built on this --
    /// which lives on api.tomtom.com. The last copy is kept on disk so a map
    /// with no network still comes up: the skeleton is reused and only the
    /// raster layers on top, which are served from the device, are drawn.
    /// Caches only, and never logged: the JSON carries the API key.
    private func baseStyle(apiKey: String, nextTo outputURL: URL) async throws -> [String: Any] {
        if let cached = cachedBaseStyles[apiKey] { return cached }
        let onDisk = outputURL.deletingLastPathComponent().appendingPathComponent(Self.baseStyleCacheFile)
        guard let url = browsingStyleURL(apiKey: apiKey) else {
            throw ComposerError.invalidStyleURL
        }
        var downloaded: Data?
        if let (data, response) = try? await URLSession.shared.data(from: url),
           let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode {
            downloaded = data
            try? data.write(to: onDisk, options: .atomic)
        }
        guard let data = downloaded ?? (try? Data(contentsOf: onDisk)) else {
            throw ComposerError.styleDownloadFailed
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ComposerError.invalidStyleJSON
        }
        cachedBaseStyles[apiKey] = json
        return json
    }

    private static let baseStyleCacheFile = "tomtom_base_style.json"

    private func browsingStyleURL(apiKey: String) -> URL? {
        var components = URLComponents(string: "https://api.tomtom.com/style/1/style/25.2.*")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "map", value: "gosdk/basic_street-light"),
            URLQueryItem(name: "traffic_incidents", value: "gosdk/incidents_light"),
            URLQueryItem(name: "traffic_flow", value: "gosdk/flow_relative-light"),
            URLQueryItem(name: "hillshade", value: "2-test/hillshade_dem-light"),
        ]
        return components?.url
    }

    private func baseRasterTemplate(apiKey: String) -> String {
        let encoded = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
        return "https://api.tomtom.com/map/1/tile/basic/main/{z}/{x}/{y}.png?key=\(encoded)"
    }

    private func rasterSource(_ source: RasterLayerSource) -> [String: Any] {
        switch source {
        case let .urlTemplate(template, tileSize, minZoom, maxZoom, _, scheme):
            return rasterTileSource(
                template: template,
                tileSize: tileSize,
                minZoom: minZoom,
                maxZoom: maxZoom,
                scheme: scheme
            )
        case let .tileJson(url):
            return ["type": "raster", "url": url]
        case let .arcGisService(serviceUrl):
            let base = serviceUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return rasterTileSource(
                template: "\(base)/tile/{z}/{y}/{x}",
                tileSize: RasterLayerSource.defaultTileSize,
                minZoom: nil,
                maxZoom: nil,
                scheme: .XYZ
            )
        }
    }

    /// TomTom's raster source grid needs half the logical display tile size.
    /// At unified zoom 12, a 512-point source must request XYZ z=11, as on
    /// MapLibre. Dividing by four on a 2x iPad instead requested z=12: the
    /// renderer read the style one level too high and its roads were shrunk
    /// into a 256-point cell. Screen scale controls image pixels, not the
    /// geographic grid or the zoom at which the style is evaluated.
    private static let tileSizeScale = 2

    private func rasterTileSource(
        template: String,
        tileSize: Int,
        minZoom: Int?,
        maxZoom: Int?,
        scheme: TileScheme
    ) -> [String: Any] {
        var source: [String: Any] = [
            "type": "raster",
            "tiles": [template],
            "tileSize": max(1, tileSize / Self.tileSizeScale),
        ]
        if let minZoom { source["minzoom"] = minZoom }
        if let maxZoom { source["maxzoom"] = maxZoom }
        if scheme == .TMS { source["scheme"] = "tms" }
        return source
    }

    private func rasterLayer(id: String, source: String, opacity: Double) -> [String: Any] {
        [
            "id": id,
            "type": "raster",
            "source": source,
            "paint": ["raster-opacity": opacity],
        ]
    }

    private func styleIdentifier(_ value: String) -> String {
        String(value.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
    }

    private enum ComposerError: Error {
        case invalidStyleURL
        case styleDownloadFailed
        case invalidStyleJSON
    }
}
