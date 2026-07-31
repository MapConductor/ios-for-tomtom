import Foundation
import MapConductorCore
import TomTomSDKMapDisplay

actor TomTomStyleComposer {
    static let shared = TomTomStyleComposer()

    private var cachedBaseStyles: [String: [String: Any]] = [:]

    func compose(
        apiKey: String,
        layers: [TomTomRasterSpec],
        outputURL: URL
    ) async throws -> StyleContainer {
        var root = try await baseStyle(apiKey: apiKey)
        var sources = root["sources"] as? [String: Any] ?? [:]
        var styleLayers = root["layers"] as? [[String: Any]] ?? []

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

    private func baseStyle(apiKey: String) async throws -> [String: Any] {
        if let cached = cachedBaseStyles[apiKey] { return cached }
        guard let url = browsingStyleURL(apiKey: apiKey) else {
            throw ComposerError.invalidStyleURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ComposerError.styleDownloadFailed
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ComposerError.invalidStyleJSON
        }
        cachedBaseStyles[apiKey] = json
        return json
    }

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

    private func rasterSource(_ source: RasterSource) -> [String: Any] {
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
                tileSize: RasterSource.defaultTileSize,
                minZoom: nil,
                maxZoom: nil,
                scheme: .XYZ
            )
        }
    }

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
            "tileSize": tileSize,
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
