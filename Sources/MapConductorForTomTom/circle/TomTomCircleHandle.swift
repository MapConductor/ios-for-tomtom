import TomTomSDKMapDisplay

/// A circle is composited from two TomTom overlays (mirrors the Mapbox renderer's fill-layer +
/// line-layer approach): the native `Circle` for the fill, and a `Line` ring for the outline.
/// TomTom's iOS `Circle` has no outline, so the stroke is drawn as a separate polyline ring.
public final class TomTomCircleHandle {
    var fill: TomTomSDKMapDisplay.Circle?
    var stroke: TomTomSDKMapDisplay.Line?

    init(fill: TomTomSDKMapDisplay.Circle?, stroke: TomTomSDKMapDisplay.Line?) {
        self.fill = fill
        self.stroke = stroke
    }
}
