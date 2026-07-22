import TomTomSDKMapDisplay

/// Native overlay types for the TomTom Orbis Maps Display SDK.
///
/// Aliased to disambiguate from `MapConductorCore` overlay DSL items (`Marker`, `Polyline`,
/// `Polygon`, `Circle`), which share the same simple names once both modules are imported.
public typealias TomTomActualMarker = TomTomSDKMapDisplay.Marker
public typealias TomTomActualPolyline = TomTomSDKMapDisplay.Line
public typealias TomTomActualPolygon = TomTomSDKMapDisplay.Polygon

// Circle は塗り（native circle）+ 枠線（polyline）の2レイヤー合成のためハンドルで保持する。
public typealias TomTomActualCircle = TomTomCircleHandle
