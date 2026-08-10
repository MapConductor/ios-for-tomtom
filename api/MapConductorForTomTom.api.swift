import Combine
import CoreGraphics
import CoreLocation
import Foundation
import MapConductorCore
import Swift
import SwiftUI
import TomTomSDKMapDisplay
import UIKit
import _Concurrency
import _StringProcessing
import _SwiftConcurrencyShims
extension MapConductorCore.MapCameraPosition {
  final public func toCameraUpdate() -> TomTomSDKMapDisplay.CameraUpdate
}
extension TomTomSDKMapDisplay.CameraProperties {
  public func toMapCameraPosition(visibleRegion: MapConductorCore.VisibleRegion? = nil, logicalTiltHint: Swift.Double? = nil) -> MapConductorCore.MapCameraPosition
}
public protocol TomTomMapDesignTypeProtocol : MapConductorCore.MapDesignTypeProtocol where Self.Identifier == Swift.String {
}
public typealias TomTomMapDesignType = any MapConductorForTomTom.TomTomMapDesignTypeProtocol
public struct TomTomMapDesign : MapConductorForTomTom.TomTomMapDesignTypeProtocol, Swift.Hashable {
  public let id: Swift.String
  public let attributionRules: [MapConductorCore.AttributionRule]
  public init(id: Swift.String, attributionRules: [MapConductorCore.AttributionRule] = [])
  public func getValue() -> Swift.String
  public var styleContainer: TomTomSDKMapDisplay.StyleContainer {
    get
  }
  public static let Standard: MapConductorForTomTom.TomTomMapDesign
  public static let Driving: MapConductorForTomTom.TomTomMapDesign
  public static let Satellite: MapConductorForTomTom.TomTomMapDesign
  public static func Create(id: Swift.String) -> MapConductorForTomTom.TomTomMapDesign
  public static func toMapDesignType(id: Swift.String) -> MapConductorForTomTom.TomTomMapDesignType
  public static func == (a: MapConductorForTomTom.TomTomMapDesign, b: MapConductorForTomTom.TomTomMapDesign) -> Swift.Bool
  public typealias Identifier = Swift.String
  public func hash(into hasher: inout Swift.Hasher)
  public var hashValue: Swift.Int {
    get
  }
}
@_Concurrency.MainActor @preconcurrency public struct TomTomMapView : SwiftUICore.View {
  @_Concurrency.MainActor @preconcurrency public init(state: MapConductorForTomTom.TomTomMapViewState, apiKey: Swift.String? = nil, cameraRestriction: MapConductorCore.CameraRestriction? = nil, onMapLoaded: MapConductorCore.OnMapLoadedHandler<MapConductorForTomTom.TomTomMapViewState>? = nil, onMapClick: MapConductorCore.OnMapEventHandler? = nil, onMapLongClick: MapConductorCore.OnMapEventHandler? = nil, onCameraMoveStart: MapConductorCore.OnCameraMoveHandler? = nil, onCameraMove: MapConductorCore.OnCameraMoveHandler? = nil, onCameraMoveEnd: MapConductorCore.OnCameraMoveHandler? = nil, sdkInitialize: (() -> Swift.Void)? = nil, @MapConductorCore.MapViewContentBuilder content: @escaping () -> MapConductorCore.MapViewContent = { MapViewContent() })
  @_Concurrency.MainActor @preconcurrency public var body: some SwiftUICore.View {
    get
  }
  public typealias Body = @_opaqueReturnTypeOf("$s018MapConductorForTomD00ddA4ViewV4bodyQrvp", 0) __
}
final public class TomTomMapViewState : MapConductorCore.MapViewState<MapConductorForTomTom.TomTomMapDesignType> {
  final public var mapViewHolder: MapConductorForTomTom.TomTomMapViewHolder? {
    get
  }
  override final public var mapDesignType: MapConductorForTomTom.TomTomMapDesignType {
    get
    set
  }
  public init(id: Swift.String, mapDesignType: MapConductorForTomTom.TomTomMapDesignType = TomTomMapDesign.Standard, cameraPosition: MapConductorCore.MapCameraPosition = .Default, uiSettings: MapConductorCore.MapUISettings = MapUISettings())
  convenience public init(mapDesignType: MapConductorForTomTom.TomTomMapDesignType = TomTomMapDesign.Standard, cameraPosition: MapConductorCore.MapCameraPosition = .Default, uiSettings: MapConductorCore.MapUISettings = MapUISettings())
  override final public func getMapViewHolder() -> MapConductorCore.AnyMapViewHolder?
  @objc deinit
}
public typealias TomTomActualMarker = TomTomSDKMapDisplay.Marker
public typealias TomTomActualPolyline = TomTomSDKMapDisplay.Line
public typealias TomTomActualPolygon = TomTomSDKMapDisplay.Polygon
public typealias TomTomActualGroundImage = TomTomSDKMapDisplay.Polygon
public typealias TomTomActualCircle = TomTomSDKMapDisplay.Polygon
final public class TomTomZoomAltitudeConverter : MapConductorCore.GroundScaleZoomAltitudeConverter {
  public static let tomtomToGoogleZoomBaseOffset: Swift.Double
  public init(zoom0Altitude: Swift.Double = AbstractZoomAltitudeConverter.defaultZoom0Altitude)
  public static func zoomOffset(at latitude: Swift.Double) -> Swift.Double
  public static func tomtomZoomToGoogleZoom(_ tomtomZoom: Swift.Double, latitude: Swift.Double = 0.0) -> Swift.Double
  public static func googleZoomToTomTomZoom(_ googleZoom: Swift.Double, latitude: Swift.Double = 0.0) -> Swift.Double
  @objc deinit
}
@_hasMissingDesignatedInitializers final public class TomTomMapViewHolder : MapConductorCore.MapViewHolderProtocol {
  final public let mapView: TomTomSDKMapDisplay.MapView
  final public let map: TomTomSDKMapDisplay.TomTomMap
  final public func toScreenOffset(position: any MapConductorCore.GeoPointProtocol) -> CoreFoundation.CGPoint?
  final public func fromScreenOffsetSync(offset: CoreFoundation.CGPoint) -> MapConductorCore.GeoPoint?
  public typealias ActualMap = TomTomSDKMapDisplay.TomTomMap
  public typealias ActualMapView = TomTomSDKMapDisplay.MapView
  @objc deinit
}
extension MapConductorForTomTom.TomTomMapView : Swift.Sendable {}
