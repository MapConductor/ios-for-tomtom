import CoreLocation
import MapConductorCore
import TomTomSDKMapDisplay
import UIKit

/// Draws a ground image with TomTom's native textured polygon support.
/// This mirrors the Android provider and avoids a tile-server/style reload for image updates.
@MainActor
final class TomTomGroundImageOverlayRenderer: AbstractGroundImageOverlayRenderer<TomTomActualGroundImage> {
    private weak var map: TomTomMap?

    init(map: TomTomMap?) {
        self.map = map
        super.init()
    }

    override func createGroundImage(state: GroundImageState) async -> TomTomActualGroundImage? {
        guard let map, let coordinates = coordinates(for: state.bounds) else { return nil }
        var options = PolygonOptions(coordinates: coordinates)
        options.fillColor = imageFillColor(opacity: state.opacity)
        options.outlineColor = .clear
        options.outlineWidth = 1
        options.textureOptions = textureOptions(image: state.image)
        options.isSelectable = true
        let polygon = try? map.addPolygon(options: options)
        polygon?.tag = groundImageTag(state.id)
        return polygon
    }

    override func updateGroundImageProperties(
        groundImage: TomTomActualGroundImage,
        current: GroundImageEntity<TomTomActualGroundImage>,
        prev: GroundImageEntity<TomTomActualGroundImage>
    ) async -> TomTomActualGroundImage? {
        let finger = current.fingerPrint
        let previous = prev.fingerPrint

        // TomTom's polygon coordinates do not reliably invalidate the native renderer.
        // Recreate for bounds changes, adding the replacement first to avoid a blank frame.
        if finger.bounds != previous.bounds {
            let replacement = await createGroundImage(state: current.state)
            map?.remove(annotation: groundImage)
            return replacement
        }
        if finger.image != previous.image {
            groundImage.textureOptions = textureOptions(image: current.state.image)
        }
        if finger.opacity != previous.opacity {
            groundImage.fillColor = imageFillColor(opacity: current.state.opacity)
        }
        groundImage.isSelectable = true
        return groundImage
    }

    override func removeGroundImage(entity: GroundImageEntity<TomTomActualGroundImage>) async {
        if let polygon = entity.groundImage {
            map?.remove(annotation: polygon)
        }
    }

    func unbind() {
        map = nil
    }

    private func textureOptions(image: UIImage) -> TextureOptions {
        var options = TextureOptions(image: image)
        options.isImageOverlay = true
        return options
    }

    private func imageFillColor(opacity: Double) -> UIColor {
        UIColor(white: 1, alpha: min(max(opacity, 0), 1))
    }

    private func coordinates(for bounds: GeoRectBounds) -> [CLLocationCoordinate2D]? {
        guard let southWest = bounds.southWest, let northEast = bounds.northEast else { return nil }
        return [
            CLLocationCoordinate2D(latitude: southWest.latitude, longitude: southWest.longitude),
            CLLocationCoordinate2D(latitude: southWest.latitude, longitude: northEast.longitude),
            CLLocationCoordinate2D(latitude: northEast.latitude, longitude: northEast.longitude),
            CLLocationCoordinate2D(latitude: northEast.latitude, longitude: southWest.longitude),
        ]
    }
}

func groundImageTag(_ id: String) -> String {
    "mapconductor-ground-image-\(id)"
}

func groundImageId(from tag: String?) -> String? {
    let prefix = "mapconductor-ground-image-"
    guard let tag, tag.hasPrefix(prefix) else { return nil }
    return String(tag.dropFirst(prefix.count))
}
