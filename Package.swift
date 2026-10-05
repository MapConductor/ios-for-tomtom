// swift-tools-version: 5.9
import Foundation
import PackageDescription

let frameworkLibraryType: Product.Library.LibraryType? =
    ProcessInfo.processInfo.environment["MAPCONDUCTOR_BUILD_XCFRAMEWORK"] == "1" ? .dynamic : nil
let usingLocalCore = FileManager.default.fileExists(atPath: "../ios-sdk-core/Package.swift")
let coreDependency: Package.Dependency = usingLocalCore
    ? .package(path: "../ios-sdk-core")
    : .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.3.1")

// TomTom Orbis Maps Display SDK (0.73.1) and its transitive closure, distributed as binary
// xcframeworks from TomTom's public artifactory. Fetch them into `Frameworks/` with
// `scripts/fetch-tomtom-sdk.sh` (they are not committed). Keep this list in sync with
// PODS in that script.
let tomtomFrameworks = [
    "TomTomSDKMapDisplay",
    "TomTomSDKCommon",
    "TomTomSDKFeatureToggle",
    "TomTomSDKLocationProvider",
    "TomTomSDKBindingMapDisplayEngineInternal",
    "TomTomSDKBindingFrameworkLoggingInternal",
    "TomTomSDKBindingMapDisplayElasticDataProviderInternal",
    "TomTomSDKMapTileStoreCommon",
    "TomTomSDKTelemetry",
    "TomTomSDKRoute",
    "TomTomSDKRoutingCommon",
]

let package = Package(
    name: "ios-for-tomtom",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "MapConductorForTomTom",
            type: frameworkLibraryType,
            targets: ["MapConductorForTomTom"]
        ),
    ],
    dependencies: [
        coreDependency,
    ],
    targets: tomtomFrameworks.map { name in
        .binaryTarget(name: name, path: "Frameworks/\(name).xcframework")
    } + [
        .target(
            name: "MapConductorForTomTom",
            dependencies: [
                .product(name: "MapConductorCore", package: "ios-sdk-core"),
            ] + tomtomFrameworks.map { .byName(name: $0) }
        ),
        .testTarget(
            name: "MapConductorForTomTomTests",
            dependencies: ["MapConductorForTomTom"]
        ),
    ]
)
