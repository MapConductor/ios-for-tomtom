# TomTom SDK for MapConductor iOS

## Description

TomTom Orbis Maps provider for the MapConductor unified mapping API, built on
[`TomTomSDKMapDisplay`](https://developer.tomtom.com/maps-sdk-ios/documentation).

`TomTomMapView` supports the same MapConductor content types as the Android
`android-for-tomtom` provider: Marker, Polyline, Polygon, Circle, GroundImage, RasterLayer and
InfoBubble.

This mirrors the Android `android-for-tomtom` module feature-for-feature:

- **Zoom calibration**: the unified zoom is Google-equivalent. `TomTomZoomAltitudeConverter` uses
  the camera latitude (`1.76 + log2(cos(latitude))`) when converting between unified and TomTom-native
  zoom; viewport dimensions and display scale need no additional correction.
- **Marker drag (custom)**: TomTom has no native marker drag. A `MarkerDragGestureRecognizer` on the
  `MapView` implements grab-on-move / click-on-release: touching a `draggable` marker owns the gesture
  and disables the map's pan (`disabledGestures = [.pan]`); movement beyond a slop starts the drag and
  the marker follows the finger; releasing without moving is treated as a tap. The marker is
  repositioned by mutating `Marker.coordinate` in place (no remove + re-create — re-creating every
  frame would freeze the app, same lesson as Android).
- **In-place updates**: TomTom's `Marker` exposes mutable `coordinate` / `image` / `isVisible`, so
  position/icon/visibility updates mutate the existing native marker.
- **Ground images**: rendered as TomTom textured polygons. Bounds changes recreate the native
  polygon because TomTom does not reliably invalidate changed polygon coordinates.
- **Raster layers**: TomTom's base style and MapConductor raster sources are composed into a local
  custom style. This also enables LocalTileServer-backed Heatmap and GeoJSON layers. Retina tile
  requests such as `@2x.png` are rendered at their requested pixel density.

## Setup

https://mapconductor.com/setup/ios/tomtom/

### API key

1. Get a TomTom Orbis Maps API key from the TomTom Developer Portal.
2. Provide it either per-view (`TomTomMapView(state:, apiKey:)`) or via `Info.plist`:

```xml
<key>TomTomAPIKey</key>
<string>YOUR_TOMTOM_API_KEY</string>
```

3. Add the TomTom CocoaPods source to your app's `Podfile`:

```ruby
source 'https://api.tomtom.com/maps-sdk-ios/cocoapods'
```

## Usage

```swift
import MapConductorForTomTom
import MapConductorCore

let state = TomTomMapViewState(
    mapDesignType: TomTomMapDesign.Standard,
    cameraPosition: MapCameraPosition(position: GeoPoint(latitude: 52.3676, longitude: 4.9041), zoom: 11)
)

TomTomMapView(state: state) {
    Marker(state: MarkerState(
        position: GeoPoint(latitude: 52.3676, longitude: 4.9041),
        icon: DefaultMarkerIcon(label: "Amsterdam"),
        draggable: true
    ))
}
```

## Components

### TomTomMapView [[docs]](https://mapconductor.com/mapview/)

The SwiftUI map view is controlled through `TomTomMapViewState`.

### Marker [[docs]](https://mapconductor.com/markers/)

Supports custom icons, click events, in-place updates, and custom dragging.

### InfoBubble [[docs]](https://mapconductor.com/info-bubble/)

Displays SwiftUI content anchored to a selected marker.

### Circle [[docs]](https://mapconductor.com/circle/)

Renders circles through the unified MapConductor API.

### Polyline [[docs]](https://mapconductor.com/polyline/)

Renders native TomTom polylines.

### Polygon [[docs]](https://mapconductor.com/polygon/)

Renders native TomTom polygons.

### Polygon Hole

Polygon holes use the same unified shape data as the other iOS providers.

### GroundImage [[docs]](https://mapconductor.com/ground-image/)

Ground images use textured polygons. Raster tile layers are also supported.

### Files

| File | Role |
| --- | --- |
| `TomTomMapView.swift` | SwiftUI view, `MapDelegate` (camera/interaction), custom drag gesture, InfoBubble wiring |
| `TomTomMapViewState.swift` | `TomTomMapViewState` |
| `controller/TomTomMapViewController.swift` | Camera / fitBounds / listeners |
| `controller/TomTomMapViewHolder.swift` | `MapView`/`TomTomMap` wrapper + coordinate↔screen |
| `TomTomMapDesign.swift` | Style/design (`StyleContainer`) |
| `MapCameraPositionExtensions.swift` | Camera conversions with latitude-aware zoom offset |
| `ZoomAltitudeConverter.swift` | Zoom↔altitude with latitude-aware TomTom calibration |
| `marker/TomTomMarkerRenderer.swift` | Native marker rendering (in-place mutation) |
| `marker/TomTomMarkerController.swift` | Marker sync + drag hit-test (`find`) |
| `polyline/`, `polygon/`, `circle/` | Native vector overlay renderers and controllers |
| `groundimage/` | Native textured-polygon GroundImage renderer and controller |
| `raster/` | Raster layer synchronization and TomTom custom-style composition |

### License

Apache License 2.0
