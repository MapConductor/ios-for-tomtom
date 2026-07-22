# MapConductor for TomTom (iOS)

TomTom Orbis Maps provider for the MapConductor unified mapping API, built on
[`TomTomSDKMapDisplay`](https://developer.tomtom.com/maps-sdk-ios/documentation).

> **Scope (current): core + markers only.**
> `TomTomMapView` / view state / controller / map design / **markers** (add/update/remove, tap,
> **custom drag**, drop/bounce animation) are implemented. Polyline / Polygon / Circle / GroundImage /
> RasterLayer are not yet implemented.

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

## Setup

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

## Files

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

## License

Apache License 2.0
