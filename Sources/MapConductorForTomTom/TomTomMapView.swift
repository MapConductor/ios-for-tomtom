import Combine
import CoreLocation
import MapConductorCore
import SwiftUI
import TomTomSDKMapDisplay
import UIKit

public struct TomTomMapView: View {
    @ObservedObject private var state: TomTomMapViewState

    private let apiKey: String?
    private let handlers: MapViewHandlers<TomTomMapViewState>
    private let content: () -> MapViewContent

    /// - Parameter apiKey: TomTom Orbis Maps API key. If `nil`, it is read from the app's
    ///   Info.plist under the `TomTomAPIKey` key.
    public init(
        state: TomTomMapViewState,
        apiKey: String? = nil,
        onMapLoaded: OnMapLoadedHandler<TomTomMapViewState>? = nil,
        onMapClick: OnMapEventHandler? = nil,
        onMapLongClick: OnMapEventHandler? = nil,
        onCameraMoveStart: OnCameraMoveHandler? = nil,
        onCameraMove: OnCameraMoveHandler? = nil,
        onCameraMoveEnd: OnCameraMoveHandler? = nil,
        sdkInitialize: (() -> Void)? = nil,
        @MapViewContentBuilder content: @escaping () -> MapViewContent = { MapViewContent() }
    ) {
        self.state = state
        self.apiKey = apiKey
        self.handlers = MapViewHandlers(
            onMapLoaded: onMapLoaded,
            onMapClick: onMapClick,
            onMapLongClick: onMapLongClick,
            onCameraMoveStart: onCameraMoveStart,
            onCameraMove: onCameraMove,
            onCameraMoveEnd: onCameraMoveEnd,
            sdkInitialize: sdkInitialize
        )
        self.content = content
    }

    public var body: some View {
        let mapContent = content()
        return MapViewBase(
            attributionRules: state.mapDesignType.attributionRules,
            camera: state.cameraPosition,
            content: mapContent
        ) {
            TomTomMapViewRepresentable(
                state: state,
                apiKey: apiKey,
                handlers: handlers,
                content: mapContent
            )
        }
    }
}

private final class TomTomWrapperView: UIView {
    let mapView: MapView
    let overlayContainer: UIView

    init(mapView: MapView, overlayContainer: UIView) {
        self.mapView = mapView
        self.overlayContainer = overlayContainer
        super.init(frame: .zero)
        addSubview(mapView)
        addSubview(overlayContainer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        mapView.frame = bounds
        overlayContainer.frame = bounds
    }
}

private struct TomTomMapViewRepresentable: UIViewRepresentable {
    @ObservedObject var state: TomTomMapViewState

    let apiKey: String?
    let handlers: MapViewHandlers<TomTomMapViewState>
    let content: MapViewContent

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, handlers: handlers)
    }

    private func resolvedApiKey() -> String {
        if let apiKey, !apiKey.isEmpty { return apiKey }
        return (Bundle.main.object(forInfoDictionaryKey: "TomTomAPIKey") as? String) ?? ""
    }

    func makeUIView(context: Context) -> TomTomWrapperView {
        if let sdkInitialize = handlers.sdkInitialize {
            Coordinator.runOnce(sdkInitialize)
        }
        let options = MapOptions(
            mapStyle: (state.mapDesignType as? TomTomMapDesign)?.styleContainer,
            apiKey: resolvedApiKey(),
            cameraUpdate: state.cameraPosition.toCameraUpdate(),
            styleMode: .main
        )
        let mapView = MapView(mapOptions: options)

        let wrapper = TomTomWrapperView(mapView: mapView, overlayContainer: context.coordinator.infoBubbleContainer)
        wrapper.backgroundColor = .clear
        context.coordinator.attachInfoBubbleContainer(to: wrapper)
        context.coordinator.mapView = mapView

        let apiKey = resolvedApiKey()
        mapView.getMapAsync { map in
            context.coordinator.onMapReady(mapView: mapView, map: map, apiKey: apiKey)
            context.coordinator.updateContent(content)
        }
        return wrapper
    }

    func updateUIView(_ uiView: TomTomWrapperView, context: Context) {
        context.coordinator.applyDesign(state.mapDesignType)
        context.coordinator.updateContent(content)
    }

    static func dismantleUIView(_ uiView: TomTomWrapperView, coordinator: Coordinator) {
        coordinator.unbind()
    }

    @MainActor
    final class Coordinator: MapViewCoordinatorBase<TomTomMapViewState>, MapDelegate {
        weak var mapView: MapView?
        private weak var map: TomTomMap?
        private var controller: TomTomMapViewController?
        private var markerController: TomTomMarkerController?
        private var polylineController: TomTomPolylineController?
        private var polygonController: TomTomPolygonController?
        private var circleController: TomTomCircleController?
        private var groundImageController: TomTomGroundImageController?
        private var rasterController: TomTomRasterLayerController?
        private var overlayScope: MapOverlayScope?
        private var infoBubbleCoordinator: InfoBubbleOverlayCoordinator?

        private var cameraMoving = false
        private var appliedDesignId: String?

        // Custom drag state (TomTom has no native marker drag).
        private var dragRecognizer: MarkerDragGestureRecognizer?
        private var pendingDragEntity: MarkerEntity<TomTomActualMarker>?
        private var draggingEntity: MarkerEntity<TomTomActualMarker>?
        private var dragDownPoint: CGPoint = .zero
        private var savedDisabledGestures: [MapGestureDisableOption] = []
        private static let dragSlop: CGFloat = 12.0

        func onMapReady(mapView: MapView, map: TomTomMap, apiKey: String) {
            self.map = map
            map.delegate = self
            // 初期スタイルは MapOptions で読み込み済みなので、同一 design の再適用を防ぐ。
            appliedDesignId = (state.mapDesignType as? TomTomMapDesign)?.id

            let controller = TomTomMapViewController(mapView: mapView, map: map)
            self.controller = controller
            state.setController(controller)
            state.setMapViewHolder(controller.typedHolder)

            let markerController = TomTomMarkerController(map: map)
            self.markerController = markerController
            let polylineController = TomTomPolylineController(map: map)
            self.polylineController = polylineController
            let polygonController = TomTomPolygonController(map: map)
            self.polygonController = polygonController
            let circleController = TomTomCircleController(map: map)
            self.circleController = circleController
            let groundImageController = TomTomGroundImageController(map: map)
            self.groundImageController = groundImageController
            let rasterController = TomTomRasterLayerController(
                map: map,
                apiKey: apiKey,
                fallbackDesign: (state.mapDesignType as? TomTomMapDesign) ?? .Standard
            )
            self.rasterController = rasterController

            // Route the simple overlays through the shared collector so each
            // controller subscribes to one source of truth instead of the map
            // host re-diffing arrays every render.
            let overlayScope = MapOverlayScope()
            self.overlayScope = overlayScope
            bindOverlayCollector(overlayScope.circleCollector, to: circleController)
            bindOverlayCollector(overlayScope.polylineCollector, to: polylineController)
            bindOverlayCollector(overlayScope.polygonCollector, to: polygonController)
            bindOverlayCollector(overlayScope.rasterLayerCollector, to: rasterController)
            bindOverlayCollector(overlayScope.groundImageCollector, to: groundImageController)

            // 円は radius 変更のたびに polygon を作り直して最前面へ来るため、
            // 描画後にポリラインを最前面へ戻す（TomTom は z-index 未対応で描画順＝追加順）。
            self.circleController?.renderer.onAfterRender = { [weak self] in
                await self?.polylineController?.bringToFront()
            }

            self.infoBubbleCoordinator = InfoBubbleOverlayCoordinator(
                container: infoBubbleContainer,
                project: { [weak map] point in
                    map?.pointForCoordinate(coordinate: CLLocationCoordinate2D(
                        latitude: point.latitude, longitude: point.longitude))
                },
                resolveMarkerStateForIcon: { [weak markerController] id, bubbleMarker in
                    markerController?.getMarkerState(for: id) ?? bubbleMarker
                },
                iconMetrics: { markerState in
                    let icon = (markerState.icon ?? DefaultMarkerIcon()).toBitmapIcon()
                    return MarkerIconMetrics(size: icon.size, anchor: icon.anchor, infoAnchor: icon.infoAnchor)
                }
            )

            markerController.renderer.animationOverlay = MarkerAnimationOverlayCoordinator(
                container: infoBubbleContainer,
                project: { [weak map] point in
                    map?.pointForCoordinate(coordinate: CLLocationCoordinate2D(
                        latitude: point.latitude, longitude: point.longitude))
                }
            )

            // Custom marker-drag gesture (grab-on-move, click-on-release).
            let recognizer = MarkerDragGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
            recognizer.shouldBeginAt = { [weak self] point in self?.dragShouldBegin(at: point) ?? false }
            mapView.addGestureRecognizer(recognizer)
            self.dragRecognizer = recognizer
        }

        func applyDesign(_ design: TomTomMapDesignType) {
            guard let map, let ttDesign = design as? TomTomMapDesign else { return }
            // updateUIView は camera 移動のたびに呼ばれるため、実際に design が変わったときだけ
            // styleContainer を差し替える。毎フレーム再設定するとスタイル再読み込みで画面が黒く点滅する。
            guard appliedDesignId != ttDesign.id else { return }
            appliedDesignId = ttDesign.id
            if let rasterController {
                rasterController.updateDesign(ttDesign)
            } else {
                map.styleContainer = ttDesign.styleContainer
            }
        }

        func updateContent(_ content: MapViewContent) {
            infoBubbleCoordinator?.syncInfoBubbles(content.infoBubbles)
            markerController?.syncMarkers(content.markers)
            overlayScope?.circleCollector.sync(content.circles.map { $0.state })
            overlayScope?.polylineCollector.sync(content.polylines.map { $0.state })
            overlayScope?.polygonCollector.sync(content.polygons.map { $0.state })
            overlayScope?.rasterLayerCollector.sync(content.rasterLayers.map { $0.state })
            overlayScope?.groundImageCollector.sync(content.groundImages.map { $0.state })
            infoBubbleCoordinator?.updateAllLayouts()
        }

        // MARK: - MapDelegate

        func map(_ map: TomTomMap, onInteraction interaction: MapInteraction) {
            switch interaction {
            case let .tapped(coordinate):
                let point = coordinate.toGeoPoint()
                controller?.notifyMapClick(point)
                onMapClick?(point)
            case let .tappedOnAnnotation(annotation, coordinate):
                // Non-draggable markers get their tap here; draggable ones are handled by the drag recognizer.
                if let marker = annotation as? TomTomActualMarker,
                   let id = marker.tag,
                   let markerState = markerController?.getMarkerState(for: id) {
                    markerController?.dispatchClick(state: markerState)
                } else if let line = annotation as? TomTomActualPolyline {
                    polylineController?.dispatchClick(forTag: line.tag, at: coordinate)
                } else if let polygon = annotation as? TomTomActualPolygon {
                    if groundImageController?.dispatchClick(forTag: polygon.tag, at: coordinate) == true {
                        break
                    } else if let tag = polygon.tag, tag.hasPrefix("circle-") {
                        // 円は "circle-" 接頭辞の Polygon として描画するため円のクリックに振り分ける。
                        circleController?.dispatchClick(forTag: String(tag.dropFirst("circle-".count)), at: coordinate)
                    } else {
                        polygonController?.dispatchClick(forTag: polygon.tag, at: coordinate)
                    }
                }
            case let .longPressed(coordinate):
                let point = coordinate.toGeoPoint()
                controller?.notifyMapLongClick(point)
                onMapLongClick?(point)
            default:
                break
            }
        }

        func map(_ map: TomTomMap, onCameraEvent event: CameraEvent) {
            switch event {
            case let .cameraChanged(properties):
                let camera = camera(from: properties)
                if !cameraMoving {
                    cameraMoving = true
                    controller?.notifyCameraMoveStart(camera)
                    onCameraMoveStart?(camera)
                }
                state.updateCameraPosition(camera)
                controller?.notifyCameraMove(camera)
                onCameraMove?(camera)
                infoBubbleCoordinator?.updateAllLayouts()
            case let .cameraSteady(properties):
                cameraMoving = false
                let camera = camera(from: properties)
                state.updateCameraPosition(camera)
                controller?.notifyCameraMoveEnd(camera)
                onCameraMoveEnd?(camera)
                infoBubbleCoordinator?.updateAllLayouts()
                performMapLoadedOnce {
                    controller?.notifyMapInitialized()
                    onMapLoaded?(state)
                }
            default:
                break
            }
        }

        private func camera(from properties: CameraProperties) -> MapCameraPosition {
            var visibleRegion: MapConductorCore.VisibleRegion?
            if let region = map?.visibleRegion {
                let lats = [region.farLeft.latitude, region.nearLeft.latitude, region.farRight.latitude, region.nearRight.latitude]
                let lngs = [region.farLeft.longitude, region.nearLeft.longitude, region.farRight.longitude, region.nearRight.longitude]
                visibleRegion = MapConductorCore.VisibleRegion(
                    bounds: GeoRectBounds(
                        southWest: GeoPoint(latitude: lats.min() ?? 0, longitude: lngs.min() ?? 0, altitude: 0),
                        northEast: GeoPoint(latitude: lats.max() ?? 0, longitude: lngs.max() ?? 0, altitude: 0)
                    ),
                    nearLeft: region.nearLeft.toGeoPoint(),
                    nearRight: region.nearRight.toGeoPoint(),
                    farLeft: region.farLeft.toGeoPoint(),
                    farRight: region.farRight.toGeoPoint()
                )
            }
            return properties.toMapCameraPosition(visibleRegion: visibleRegion)
        }

        // MARK: - Custom marker drag

        private func dragShouldBegin(at point: CGPoint) -> Bool {
            guard let map, let markerController,
                  let coordinate = map.coordinateForPoint(point: point) else { return false }
            guard let entity = markerController.find(position: coordinate.toGeoPoint()),
                  entity.state.draggable else { return false }
            pendingDragEntity = entity
            dragDownPoint = point
            return true
        }

        @objc private func handleDrag(_ recognizer: MarkerDragGestureRecognizer) {
            guard let mapView, let map, let markerController else { return }
            let point = recognizer.location(in: mapView)

            switch recognizer.state {
            case .began:
                // Freeze the map so it doesn't pan while we drag the marker.
                savedDisabledGestures = map.disabledGestures
                map.disabledGestures = savedDisabledGestures + [.pan, .doubleTapAndPan]
            case .changed:
                guard let pending = pendingDragEntity else { return }
                if draggingEntity == nil {
                    let dx = point.x - dragDownPoint.x
                    let dy = point.y - dragDownPoint.y
                    guard (dx * dx + dy * dy).squareRoot() > Self.dragSlop else { return }
                    draggingEntity = pending
                    markerController.dispatchDragStart(state: pending.state)
                }
                if let coordinate = map.coordinateForPoint(point: point), let marker = pending.marker {
                    marker.coordinate = coordinate
                    pending.state.position = coordinate.toGeoPoint()
                    markerController.dispatchDrag(state: pending.state)
                    infoBubbleCoordinator?.updateInfoBubblePosition(for: pending.state.id)
                }
            case .ended, .cancelled, .failed:
                if let dragging = draggingEntity {
                    markerController.dispatchDragEnd(state: dragging.state)
                } else if let pending = pendingDragEntity {
                    // No movement → treat as a tap on the (draggable) marker.
                    markerController.dispatchClick(state: pending.state)
                }
                map.disabledGestures = savedDisabledGestures
                savedDisabledGestures = []
                pendingDragEntity = nil
                draggingEntity = nil
            default:
                break
            }
        }

        func unbind() {
            state.setController(nil)
            state.setMapViewHolder(nil)
            if let recognizer = dragRecognizer { mapView?.removeGestureRecognizer(recognizer) }
            dragRecognizer = nil
            map?.delegate = nil
            markerController?.renderer.animationOverlay?.unbind()
            markerController?.unbind()
            markerController = nil
            polylineController?.unbind()
            polylineController = nil
            polygonController?.unbind()
            polygonController = nil
            circleController?.unbind()
            circleController = nil
            groundImageController?.unbind()
            groundImageController = nil
            rasterController?.unbind()
            rasterController = nil
            overlayScope?.clear()
            overlayScope = nil
            infoBubbleCoordinator?.unbind()
            infoBubbleCoordinator = nil
            controller = nil
            map = nil
            mapView = nil
        }
    }
}

/// A gesture recognizer that only recognizes when the initial touch lands on a draggable marker.
/// It then owns the gesture (grab-on-move / click-on-release), preventing the map from panning.
final class MarkerDragGestureRecognizer: UIGestureRecognizer {
    var shouldBeginAt: ((CGPoint) -> Bool)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first, let view else {
            state = .failed
            return
        }
        state = (shouldBeginAt?(touch.location(in: view)) == true) ? .began : .failed
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        if state == .began || state == .changed { state = .changed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = (state == .began || state == .changed) ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .cancelled
    }
}
