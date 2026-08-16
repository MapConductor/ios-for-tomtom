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
    private let cameraRestriction: CameraRestriction?
    private let content: () -> MapViewContent

    /// - Parameter apiKey: TomTom Orbis Maps API key. If `nil`, it is read from the app's
    ///   Info.plist under the `TomTomAPIKey` key.
    public init(
        state: TomTomMapViewState,
        apiKey: String? = nil,
        cameraRestriction: CameraRestriction? = nil,
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
        self.cameraRestriction = cameraRestriction
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
        // The provider's registry is in scope only while content is being assembled —
        // the same window in which Compose provides `LocalMapServiceRegistry` around the
        // content lambda. Bracketing the pass lets a removed plugin be noticed.
        let support = state.serviceRegistry.get(MarkerRenderingSupportKey.self)
        support?.beginContentPass()
        let mapContent = MapServiceRegistryScope.with(state.serviceRegistry) { content() }
        support?.endContentPass()
        return MapViewBase(
            attributionRules: state.mapDesignType.attributionRules,
            camera: state.cameraPosition,
            content: mapContent
        ) {
            TomTomMapViewRepresentable(
                state: state,
                cameraRestriction: cameraRestriction,
                apiKey: apiKey,
                handlers: handlers,
                content: mapContent
            )
        }
    }
}
private struct TomTomMapViewRepresentable: UIViewRepresentable {
    @ObservedObject var state: TomTomMapViewState
    let cameraRestriction: CameraRestriction?

    let apiKey: String?
    let handlers: MapViewHandlers<TomTomMapViewState>
    let content: MapViewContent

    func makeCoordinator() -> TomTomMapHost {
        TomTomMapHost(state: state, handlers: handlers)
    }

    func makeUIView(context: Context) -> UIView {
        // RN のホストと同じ入口を通す。手順が二重になっていると片方だけ直る。
        context.coordinator.makeMapView(
            apiKey: apiKey,
            cameraRestriction: cameraRestriction,
            content: content
        )
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // 制限値が変わったときだけ再適用する。
        context.coordinator.applyCameraRestriction(cameraRestriction)
        context.coordinator.applyDesign(state.mapDesignType)
        context.coordinator.updateGestures(state.uiSettings)
        context.coordinator.updateContent(content)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: TomTomMapHost) {
        coordinator.unbind()
    }
}
