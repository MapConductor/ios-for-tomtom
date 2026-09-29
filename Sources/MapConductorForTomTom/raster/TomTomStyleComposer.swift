import Foundation
import UIKit
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
        var root = try await baseStyle(apiKey: apiKey)
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

    /// この SDK は宣言した `tileSize` より**大きくタイルを敷き、その倍率が画面倍率で変わる**。
    ///
    /// MapConductor の `tileSize` は「1 枚のタイルが覆うレイアウト単位（ポイント）」で、
    /// MapLibre はそのとおりに敷く。同じスタイル JSON を渡しているのに、この SDK は
    /// 粗いズームのタイルを取ってきて引き伸ばす。宣言をあらかじめ割っておくと揃う。
    ///
    /// 実測（地図ズーム 13、`tileSize` 512 の GeoJSON レイヤ。正しい要求は z=12）:
    ///
    /// | 画面 | 宣言 | 要求されるタイル z | 線の太さ（MapLibre 比） |
    /// |---|---|---|---|
    /// | 3x iPhone | 512 | 11 | 2.0 倍 |
    /// | 3x iPhone | **256（÷2）** | **12** | **1.0 倍** |
    /// | 2x iPad | 256（÷2） | 11 | 1.8 倍 |
    /// | 2x iPad | **128（÷4）** | **12** | **1.0 倍** |
    ///
    /// つまり必要な除数は 3x で 2、2x で 4。エンジンの式は非公開なので、これは
    /// **理屈ではなく較正**である。未知の倍率（1x など）は安全側の 2 に倒す
    /// （粗い側にずれても表示は太くなるだけで、欠けはしない）。
    ///
    /// ベースの地図タイル（mc-base-raster、256）も同じ経路で割っている。ここを
    /// 除外するとベースだけ倍の大きさで描かれてぼやける。
    ///
    /// **ここを外すと GeoJSON レイヤ・ヒートマップ・タイル方式マーカーが揃って
    /// 太く・ぼやけて描かれる。** android-for-tomtom は別実装（TILE_SIZE_SCALE = 2 固定。
    /// あちらは densityDpi の系で、実測 6px = MapLibre と一致済み）。
    private static let tileSizeScale: Int = {
        // 起動後 UIKit が使える前になることはない（compose は地図生成後にしか呼ばれない）。
        let displayScale = Int(UIScreen.main.scale.rounded())
        return displayScale <= 2 ? 4 : 2
    }()

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
