import CoreLocation
import MapConductorCore
import TomTomSDKMapDisplay
import UIKit

/// Renders MapConductor markers as native TomTom `Marker`s.
///
/// TomTom's `Marker` exposes mutable `coordinate`, `image` and `isVisible`, so position/visibility/
/// icon changes update the existing instance in place (no remove + re-create). This is important:
/// re-creating a marker on every drag frame floods the main thread and freezes the app (mirrors the
/// Android fix).
@MainActor
final class TomTomMarkerRenderer: MarkerOverlayRendererProtocol {
    typealias ActualMarker = TomTomActualMarker

    weak var map: TomTomMap?

    var animateStartListener: OnMarkerEventHandler?
    var animateEndListener: OnMarkerEventHandler?

    /// When set, drop/bounce animations run on the screen-space overlay layer (projection-independent);
    /// the native marker is hidden for the duration via `isVisible`.
    var animationOverlay: MarkerAnimationOverlayCoordinator?

    init(map: TomTomMap?) {
        self.map = map
    }

    func onAdd(data: [MarkerOverlayAddParams]) async -> [TomTomActualMarker?] {
        guard let map else { return data.map { _ in nil } }
        return data.map { params in
            var options = MarkerOptions(
                coordinate: params.state.position.toCoordinate(),
                pinImage: params.bitmapIcon.bitmap,
                tag: params.state.id
            )
            options.placementAnchor = params.bitmapIcon.anchor
            let marker = try? map.addMarker(options: options)
            marker?.isVisible = params.state.getAnimation() == nil
            return marker
        }
    }

    func onChange(data: [MarkerOverlayChangeParams<TomTomActualMarker>]) async -> [TomTomActualMarker?] {
        data.map { params in
            guard let marker = params.prev.marker else { return nil }
            marker.coordinate = params.current.state.position.toCoordinate()
            marker.image = params.bitmapIcon.bitmap
            marker.placementAnchor = params.bitmapIcon.anchor
            if params.current.state.getAnimation() == nil {
                marker.isVisible = params.current.visible
            }
            return marker
        }
    }

    func onRemove(data: [MarkerEntity<TomTomActualMarker>]) async {
        for entity in data {
            if let marker = entity.marker {
                map?.remove(annotation: marker)
            }
        }
    }

    func onAnimate(entity: MarkerEntity<TomTomActualMarker>) async {
        guard let marker = entity.marker, let animation = entity.state.getAnimation() else { return }

        let duration: CFTimeInterval = animation == .Bounce ? 2.0 : 0.3

        if let overlay = animationOverlay {
            marker.isVisible = false
            animateStartListener?(entity.state)
            let icon = (entity.state.icon ?? DefaultMarkerIcon()).toBitmapIcon()
            overlay.start(MarkerAnimationOverlayEntry(
                id: entity.state.id,
                state: entity.state,
                icon: icon,
                animation: animation,
                duration: duration,
                onFinished: { [weak self] in
                    marker.isVisible = true
                    entity.state.animate(nil)
                    self?.animateEndListener?(entity.state)
                }
            ))
            return
        }

        // No overlay available: just show the marker at its final position.
        marker.isVisible = true
        entity.state.animate(nil)
    }

    func onPostProcess() async {
        // No-op: TomTom markers are updated directly in place.
    }

    /// Reposition a marker's native coordinate directly (used by the custom drag gesture).
    func moveMarker(_ marker: TomTomActualMarker, to coordinate: CLLocationCoordinate2D) {
        marker.coordinate = coordinate
    }

    func unbind() {
        animationOverlay?.unbind()
        animationOverlay = nil
        map = nil
    }
}
