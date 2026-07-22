Pod::Spec.new do |s|
  s.name = "MapConductorForTomTom"
  s.version = "1.1.4"
  s.summary = "MapConductor's TomTom Orbis Maps provider."
  s.license = { :type => "Apache-2.0", :file => "LICENSE" }
  s.author = "MapConductor"
  s.homepage = "https://github.com/MapConductor/ios-for-tomtom"
  s.source = { :path => __dir__ }
  s.platform = :ios, "16.0"
  s.swift_version = "5.9"
  s.source_files = "Sources/MapConductorForTomTom/**/*.swift"

  # TomTom Orbis Maps SDK is distributed via TomTom's CocoaPods spec repo
  # (source 'https://api.tomtom.com/maps-sdk-ios/cocoapods' in the consuming Podfile).
  # Compiled from source so the vendor's binary frameworks are linked fresh into the
  # consuming app (never embedded into a prebuilt MapConductor xcframework).
  s.dependency "TomTomSDKMapDisplay"
  s.dependency "MapConductorCore"
end
