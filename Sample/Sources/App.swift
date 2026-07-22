import SwiftUI
import UIKit
import MapConductorForTomTom
import MapConductorCore

private let amsterdam = GeoPoint(latitude: 52.3676, longitude: 4.9041, altitude: 0)
private let route: [GeoPoint] = [
    GeoPoint(latitude: 52.40, longitude: 4.85, altitude: 0),
    GeoPoint(latitude: 52.38, longitude: 4.92, altitude: 0),
    GeoPoint(latitude: 52.35, longitude: 4.88, altitude: 0),
    GeoPoint(latitude: 52.33, longitude: 4.95, altitude: 0),
]
private let area: [GeoPoint] = [
    GeoPoint(latitude: 52.36, longitude: 4.80, altitude: 0),
    GeoPoint(latitude: 52.40, longitude: 4.82, altitude: 0),
    GeoPoint(latitude: 52.39, longitude: 4.87, altitude: 0),
    GeoPoint(latitude: 52.35, longitude: 4.86, altitude: 0),
]

@main
struct TomTomSampleApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @StateObject private var state = TomTomMapViewState(
        mapDesignType: TomTomMapDesign.Standard,
        cameraPosition: MapCameraPosition(position: amsterdam, zoom: 11)
    )
    @State private var selected: MarkerState?

    private let markerState = MarkerState(
        position: amsterdam,
        icon: DefaultMarkerIcon(label: "Amsterdam"),
        draggable: true,
        onClick: { _ in }
    )

    var body: some View {
        TomTomMapView(state: state) {
            Marker(state: markerState)
            Circle(state: CircleState(
                center: amsterdam, radiusMeters: 1500,
                fillColor: UIColor.systemBlue.withAlphaComponent(0.25)
            ))
            Polyline(state: PolylineState(points: route, strokeColor: .red, strokeWidth: 4))
            Polygon(state: PolygonState(
                points: area, strokeColor: UIColor(red: 0, green: 0.5, blue: 0, alpha: 1),
                strokeWidth: 2, fillColor: UIColor.green.withAlphaComponent(0.3)
            ))
        }
        .ignoresSafeArea()
    }
}
