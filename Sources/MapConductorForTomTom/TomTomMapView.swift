import Combine
import CoreLocation
import MapConductorCore
import SwiftUI
import TomTomSDKMapDisplay
import UIKit

public struct TomTomMapView: View {
    @ObservedObject private var state: TomTomMapViewState

    private let apiKey: String?
    private let onMapLoaded: OnMapLoadedHandler<TomTomMapViewState>?
    private let onMapClick: OnMapEventHandler?
    private let onMapLongClick: OnMapEventHandler?
    private let onCameraMoveStart: OnCameraMoveHandler?
    private let onCameraMove: OnCameraMoveHandler?
    private let onCameraMoveEnd: OnCameraMoveHandler?
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
        @MapViewContentBuilder content: @escaping () -> MapViewContent = { MapViewContent() }
    ) {
        self.state = state
        self.apiKey = apiKey
        self.onMapLoaded = onMapLoaded
        self.onMapClick = onMapClick
        self.onMapLongClick = onMapLongClick
        self.onCameraMoveStart = onCameraMoveStart
        self.onCameraMove = onCameraMove
        self.onCameraMoveEnd = onCameraMoveEnd
        self.content = content
    }

    public var body: some View {
        let mapContent = content()
        return ZStack {
            TomTomMapViewRepresentable(
                state: state,
                apiKey: apiKey,
                onMapLoaded: onMapLoaded,
                onMapClick: onMapClick,
                onMapLongClick: onMapLongClick,
                onCameraMoveStart: onCameraMoveStart,
                onCameraMove: onCameraMove,
                onCameraMoveEnd: onCameraMoveEnd,
                content: mapContent
            )
            ForEach(0..<mapContent.views.count, id: \.self) { index in
                mapContent.views[index]
            }
            MapAttributionOverlay(
                designRules: state.mapDesignType.attributionRules,
                rasterLayers: mapContent.rasterLayers,
                camera: state.cameraPosition
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
    let onMapLoaded: OnMapLoadedHandler<TomTomMapViewState>?
    let onMapClick: OnMapEventHandler?
    let onMapLongClick: OnMapEventHandler?
    let onCameraMoveStart: OnCameraMoveHandler?
    let onCameraMove: OnCameraMoveHandler?
    let onCameraMoveEnd: OnCameraMoveHandler?
    let content: MapViewContent

    func makeCoordinator() -> Coordinator {
        Coordinator(
            state: state,
            onMapLoaded: onMapLoaded,
            onMapClick: onMapClick,
            onMapLongClick: onMapLongClick,
            onCameraMoveStart: onCameraMoveStart,
            onCameraMove: onCameraMove,
            onCameraMoveEnd: onCameraMoveEnd
        )
    }

    private func resolvedApiKey() -> String {
        if let apiKey, !apiKey.isEmpty { return apiKey }
        return (Bundle.main.object(forInfoDictionaryKey: "TomTomAPIKey") as? String) ?? ""
    }

    func makeUIView(context: Context) -> TomTomWrapperView {
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

        mapView.getMapAsync { map in
            context.coordinator.onMapReady(mapView: mapView, map: map)
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
    final class Coordinator: NSObject, MapDelegate {
        private let state: TomTomMapViewState
        private let onMapLoaded: OnMapLoadedHandler<TomTomMapViewState>?
        private let onMapClick: OnMapEventHandler?
        private let onMapLongClick: OnMapEventHandler?
        private let onCameraMoveStart: OnCameraMoveHandler?
        private let onCameraMove: OnCameraMoveHandler?
        private let onCameraMoveEnd: OnCameraMoveHandler?

        weak var mapView: MapView?
        private weak var map: TomTomMap?
        private var controller: TomTomMapViewController?
        private var markerController: TomTomMarkerController?
        private var polylineController: TomTomPolylineController?
        private var polygonController: TomTomPolygonController?
        private var circleController: TomTomCircleController?
        private var infoBubbleCoordinator: InfoBubbleOverlayCoordinator?

        private var didCallMapLoaded = false
        private var cameraMoving = false
        private var appliedDesignId: String?
        fileprivate let infoBubbleContainer = PassthroughContainerView()

        // Custom drag state (TomTom has no native marker drag).
        private var dragRecognizer: MarkerDragGestureRecognizer?
        private var pendingDragEntity: MarkerEntity<TomTomActualMarker>?
        private var draggingEntity: MarkerEntity<TomTomActualMarker>?
        private var dragDownPoint: CGPoint = .zero
        private var savedDisabledGestures: [MapGestureDisableOption] = []
        private static let dragSlop: CGFloat = 12.0

        init(
            state: TomTomMapViewState,
            onMapLoaded: OnMapLoadedHandler<TomTomMapViewState>?,
            onMapClick: OnMapEventHandler?,
            onMapLongClick: OnMapEventHandler?,
            onCameraMoveStart: OnCameraMoveHandler?,
            onCameraMove: OnCameraMoveHandler?,
            onCameraMoveEnd: OnCameraMoveHandler?
        ) {
            self.state = state
            self.onMapLoaded = onMapLoaded
            self.onMapClick = onMapClick
            self.onMapLongClick = onMapLongClick
            self.onCameraMoveStart = onCameraMoveStart
            self.onCameraMove = onCameraMove
            self.onCameraMoveEnd = onCameraMoveEnd
        }

        func onMapReady(mapView: MapView, map: TomTomMap) {
            self.map = map
            map.delegate = self
            // 初期スタイルは MapOptions で読み込み済みなので、同一 design の再適用を防ぐ。
            appliedDesignId = (state.mapDesignType as? TomTomMapDesign)?.id

            let controller = TomTomMapViewController(mapView: mapView, map: map)
            self.controller = controller
            state.setController(controller)
            state.setMapViewHolder(controller.holder)

            let markerController = TomTomMarkerController(map: map)
            self.markerController = markerController
            self.polylineController = TomTomPolylineController(map: map)
            self.polygonController = TomTomPolygonController(map: map)
            self.circleController = TomTomCircleController(map: map)

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
            map.styleContainer = ttDesign.styleContainer
        }

        func updateContent(_ content: MapViewContent) {
            infoBubbleCoordinator?.syncInfoBubbles(content.infoBubbles)
            markerController?.syncMarkers(content.markers)
            polylineController?.syncPolylines(content.polylines)
            polygonController?.syncPolygons(content.polygons)
            circleController?.syncCircles(content.circles)
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
                    // 円の枠線 polyline は円のクリックとして扱う（合成 circle の stroke レイヤー）。
                    if let tag = line.tag, tag.hasPrefix("circle-stroke-") {
                        circleController?.dispatchClick(forTag: String(tag.dropFirst("circle-stroke-".count)), at: coordinate)
                    } else {
                        polylineController?.dispatchClick(forTag: line.tag, at: coordinate)
                    }
                } else if let polygon = annotation as? TomTomActualPolygon {
                    polygonController?.dispatchClick(forTag: polygon.tag, at: coordinate)
                } else if let circle = annotation as? TomTomSDKMapDisplay.Circle {
                    circleController?.dispatchClick(forTag: circle.tag, at: coordinate)
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
                if !didCallMapLoaded {
                    didCallMapLoaded = true
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

        // MARK: - InfoBubble container

        func attachInfoBubbleContainer(to hostView: UIView) {
            guard infoBubbleContainer.superview !== hostView else { return }
            infoBubbleContainer.backgroundColor = .clear
            infoBubbleContainer.isUserInteractionEnabled = true
            infoBubbleContainer.frame = hostView.bounds
            infoBubbleContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            hostView.addSubview(infoBubbleContainer)
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
