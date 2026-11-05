import Combine
import CoreGraphics
@_spi(MapConductorDriver) import MapConductorCore
import TomTomSDKMapDisplay
import UIKit

/// TomTom 用マーカーコントローラ。
///
/// 他プロバイダと同じく、`minMarkerCount` 以上の静的マーカーは ``MarkerTileRenderer`` で
/// PNG タイルに描き、ローカルタイルサーバ経由のラスター層として載せる。数万本の
/// ネイティブマーカーを常駐させない。ドラッグ可能なものとアニメーション付きのものは
/// ネイティブのマーカーで描く（ドラッグはネイティブのマーカーを直接動かすため）。
///
/// TomTom SDK には実行時に層を足す API が無いので、層の実体化は地図ホストに任せる。
/// ``markerTileRasterLayerCallback`` で受けた ``RasterLayerState`` を content のラスター層に
/// 合流させ、``TomTomRasterLayerController`` がスタイルを組み直す。android-for-tomtom と同じ形。
@MainActor
final class TomTomMarkerController: AbstractMarkerController<TomTomActualMarker, TomTomMarkerRenderer> {
    private weak var map: TomTomMap?

    private var markerStatesById: [String: MarkerState] = [:]
    private var markerSubscriptions: [String: AnyCancellable] = [:]

    // MARK: - Marker tiling

    var tilingOptions: MarkerTilingOptions = .Default
    /// タイル層が変わったときに呼ぶ。nil は層を外す。
    var markerTileRasterLayerCallback: ((RasterLayerState?) -> Void)?
    private var tileRenderer: MarkerTileRenderer<TomTomActualMarker>?
    private var tileRouteId: String?
    /// タイル URL の版。マーカーが変わるたびに上げ、地図に描画済みのタイルを取り直させる。
    private var tileVersion: Int64 = 0
    private var tiledMarkerIds: Set<String> = []
    private var tileRefreshScheduled = false
    private let defaultMarkerIconForTiling: BitmapIcon = DefaultMarkerIcon().toBitmapIcon()

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
        // The base `find` is nonisolated; our drag hit-test always runs on the main thread
        // (invoked from the gesture handler), so assume main-actor isolation to touch `map`.
        return MainActor.assumeIsolated {
            guard let map,
                  let touchPoint = map.pointForCoordinate(coordinate: position.toCoordinate())
            else {
                return nil
            }
            // タップ点の周りを候補にし、指の下にアイコン（ラベル込み）があるものを優先する。
            let project: (GeoPointProtocol) -> CGPoint? = { map.pointForCoordinate(coordinate: $0.toCoordinate()) }
            guard let bounds = MarkerHitTest.searchBounds(
                position: position,
                touchScreen: touchPoint,
                project: project
            ) else { return nil }
            return MarkerHitTest.pick(
                touchScreen: touchPoint,
                candidates: markerManager.findMarkersInBounds(bounds),
                state: { $0.state },
                project: project
            )
        }
    }

    override func add(data: [MarkerState]) async {
        guard tilingOptions.enabled else {
            await super.add(data: data)
            return
        }
        if tileRenderer == nil { setupTileRenderer() }

        let shouldTileAll = data.count >= tilingOptions.minMarkerCount
        var localTiledMarkerIds = tiledMarkerIds
        let result = await MarkerIngestionEngine.ingest(
            data: data,
            markerManager: markerManager,
            renderer: renderer,
            defaultMarkerIcon: defaultMarkerIconForTiling,
            tilingEnabled: tilingOptions.enabled,
            tiledMarkerIds: &localTiledMarkerIds,
            // ドラッグはネイティブのマーカーを指で動かすので、タイルには入れない。
            shouldTile: { [shouldTileAll] state in
                shouldTileAll && !state.draggable && state.getAnimation() == nil
            }
        )
        tiledMarkerIds = localTiledMarkerIds

        if result.tiledDataChanged, let tileRenderer {
            tileRenderer.invalidate()
            tileVersion += 1
            updateTileLayer(hasTiledMarkers: result.hasTiledMarkers)
        }
    }

    /// タイル担当のマーカーが変わったら、タイルを描き直させる。
    ///
    /// タイル担当のマーカーはネイティブのマーカーを持たないので、基底の `update` は
    /// 管理表を書き換えるだけで地図には何も届かない。
    override func update(state: MarkerState) async {
        await super.update(state: state)
        guard tiledMarkerIds.contains(state.id) else { return }
        scheduleTileRefresh()
    }

    /// 描き直しは 1 回にまとめる。TomTom では層を変えるたびにスタイルを組み直すので、
    /// 数百本が続けて変わったときに 1 本ごとに走らせるわけにはいかない。
    private func scheduleTileRefresh() {
        guard !tileRefreshScheduled else { return }
        tileRefreshScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.tileRefreshScheduled = false
            guard let tileRenderer = self.tileRenderer else { return }
            tileRenderer.invalidate()
            self.tileVersion += 1
            self.updateTileLayer(hasTiledMarkers: !self.tiledMarkerIds.isEmpty)
        }
    }

    private static var retinaAwareTileSize: Int {
        256 * max(1, Int(UIScreen.main.scale))
    }

    private func setupTileRenderer() {
        let routeId = "mapconductor-tomtom-markers-\(UUID().uuidString)"
        let contentScale = Double(UIScreen.main.scale)
        let baseCallback = tilingOptions.iconScaleCallback
        let scaledCallback: ((MarkerState, Int) -> Double)? = { state, zoom in
            (baseCallback?(state, zoom) ?? 1.0) * contentScale
        }
        let renderer = MarkerTileRenderer<TomTomActualMarker>(
            markerManager: markerManager,
            tileSize: Self.retinaAwareTileSize,
            cacheSizeBytes: tilingOptions.cacheSize,
            debugTileOverlay: tilingOptions.debugTileOverlay,
            iconScaleCallback: scaledCallback,
            declutterPx: tilingOptions.declutterPx
        )
        TileServerRegistry.get().register(routeId: routeId, provider: renderer)
        tileRenderer = renderer
        tileRouteId = routeId
    }

    private func updateTileLayer(hasTiledMarkers: Bool) {
        guard hasTiledMarkers, let routeId = tileRouteId, let tileRenderer else {
            markerTileRasterLayerCallback?(nil)
            return
        }
        // 版は URL に入れる。同じ URL のままだと地図は描画済みのタイルを取り直さない。
        let urlTemplate = TileServerRegistry.get().urlTemplate(
            routeId: routeId,
            tileSize: tileRenderer.tileSize,
            cacheKey: "v\(tileVersion)"
        )
        // 層の tileSize は画面上の大きさ（pt）。タイルは 1 枚 256pt を画面倍率の画素で焼く。
        markerTileRasterLayerCallback?(RasterLayerState(
            source: .urlTemplate(template: urlTemplate, tileSize: 256),
            id: "marker-tile-\(routeId)"
        ))
    }

    /// タイル担当のマーカーのタップ判定。`screenPoint` は地図ビューのポイント座標。
    ///
    /// タイルのマーカーは annotation ではないので `.tappedOnAnnotation` には来ない。
    /// 地図のタップ（`.tapped`）からここを通して拾う。
    func handleTiledMarkerTap(at screenPoint: CGPoint, zoom: Double) -> Bool {
        guard !tiledMarkerIds.isEmpty, let map, let tileRenderer else { return false }
        let state = tileRenderer.hitTest(
            screenPoint: screenPoint,
            markerIds: tiledMarkerIds,
            zoom: Int(zoom.rounded()),
            unproject: { point in map.coordinateForPoint(point: point)?.toGeoPoint() },
            project: { point in map.pointForCoordinate(coordinate: point.toCoordinate()) }
        )
        guard let state else { return false }
        dispatchClick(state: state)
        return true
    }

    func getMarkerState(for id: String) -> MarkerState? {
        markerManager.getEntity(id)?.state
    }

    /// 同一一覧の再送を見抜く門番。詳細は型のコメントに。
    private var syncIdentity = MarkerListIdentity()

    func syncMarkers(_ markers: [MapConductorCore.Marker]) {
        // 同じ一覧の再送は入口で帰す。SwiftUI はカメラが動くたびに body を
        // 再評価し、そのたびに全マーカーがここへ来る。なぜそれが実害か
        // （144k 件で操作の 89% が凍った）は core の MarkerListIdentity に。
        guard syncIdentity.shouldProcess(markers) else {
            _ = markers // 何も要らない。既に全部届いている。
            return
        }
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
        if let routeId = tileRouteId {
            TileServerRegistry.get().unregister(routeId: routeId)
        }
        tileRenderer = nil
        tileRouteId = nil
        tiledMarkerIds.removeAll()
        markerTileRasterLayerCallback = nil
        markerSubscriptions.values.forEach { $0.cancel() }
        markerSubscriptions.removeAll()
        markerStatesById.removeAll()
        renderer.unbind()
        map = nil
        destroy()
    }
}
