import MapConductorCore
import TomTomSDKMapDisplay

public protocol TomTomMapDesignTypeProtocol: MapDesignTypeProtocol where Identifier == String {}

public typealias TomTomMapDesignType = any TomTomMapDesignTypeProtocol

/// Map style/design for TomTom Orbis.
///
/// `getValue()` returns a stable string key (used for equality/persistence). The actual
/// `StyleContainer` applied to the map is `styleContainer`. Light/dark are handled by
/// `StyleMode` on the map, so each standard style already includes both.
public struct TomTomMapDesign: TomTomMapDesignTypeProtocol, Hashable {
    public let id: String
    public let attributionRules: [AttributionRule]

    public init(id: String, attributionRules: [AttributionRule] = []) {
        self.id = id
        self.attributionRules = attributionRules
    }

    public func getValue() -> String { id }

    /// The TomTom style container to load for this design.
    public var styleContainer: StyleContainer {
        switch id {
        case Self.Standard.id: return .defaultStyle
        case Self.Driving.id: return .drivingStyle
        case Self.Satellite.id: return .satelliteStyle
        default: return .defaultStyle
        }
    }

    /// Default (browsing) style.
    public static let Standard = TomTomMapDesign(id: "standard")
    /// Navigation-oriented style.
    public static let Driving = TomTomMapDesign(id: "driving")
    /// Satellite imagery style.
    public static let Satellite = TomTomMapDesign(id: "satellite")

    public static func Create(id: String) -> TomTomMapDesign {
        switch id {
        case Standard.id: return Standard
        case Driving.id: return Driving
        case Satellite.id: return Satellite
        default: return Standard
        }
    }

    public static func toMapDesignType(id: String) -> TomTomMapDesignType {
        Create(id: id)
    }
}
