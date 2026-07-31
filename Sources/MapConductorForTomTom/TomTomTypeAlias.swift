import TomTomSDKMapDisplay

/// Native overlay types for the TomTom Orbis Maps Display SDK.
///
/// Aliased to disambiguate from `MapConductorCore` overlay DSL items (`Marker`, `Polyline`,
/// `Polygon`, `Circle`), which share the same simple names once both modules are imported.
public typealias TomTomActualMarker = TomTomSDKMapDisplay.Marker
public typealias TomTomActualPolyline = TomTomSDKMapDisplay.Line
public typealias TomTomActualPolygon = TomTomSDKMapDisplay.Polygon
public typealias TomTomActualGroundImage = TomTomSDKMapDisplay.Polygon

// Circle は単一の native Polygon（64分割リング）として描画する。
public typealias TomTomActualCircle = TomTomSDKMapDisplay.Polygon
