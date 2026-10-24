# TomTom Orbis Maps SDK の `TomTomSDKMapDisplay` を CocoaPods から引くためだけの spec。
#
# TomTom は iOS SDK を CocoaPods の spec repo では配っていない（`MapConductorForTomTom.podspec`
# が挙げている `https://api.tomtom.com/maps-sdk-ios/cocoapods` は 404 を返す。2026-08-19 実測）。
# 配っているのは公開 artifactory 上の tarball だけで、`scripts/fetch-tomtom-sdk.sh` が
# SPM の binaryTarget 用に落としているのと同じものである。
#
# **バイナリは MapConductor 側に一切置かない**（TomTom の SDK を再配布する権利は無い）。
# このファイルはメタデータだけで、実体は毎回 TomTom の artifactory から降りてくる。
# ios-for-arcgis/ArcGIS.podspec と同じ考え方で、SPM 利用者と CocoaPods 利用者が
# 同じ tarball・同じ checksum のバイナリを掴む。
#
# バージョンを上げるときは、`scripts/fetch-tomtom-sdk.sh` の VER と Package.swift の
# `tomtomFrameworks`、そしてここの s.version / :sha256 を**同時に**合わせること
# （片方だけ上げると SPM 経路と CocoaPods 経路で別バージョンをビルドすることになる）。
# 依存関係は tarball 同梱の podspec の `s.ios.dependency` を写したもので、
# TomTom 側にリゾルバが無いため VER 変更時は手で追随する必要がある。

Pod::Spec.new do |s|
  s.name             = 'TomTomSDKMapDisplay'
  s.version          = '0.74.0'
  s.summary          = 'TomTomSDKMapDisplay'
  s.homepage         = 'https://developer.tomtom.com/'
  s.license          = { :type => 'Copyright', :text => 'Copyright 2022 TomTom N.V., https://developer.tomtom.com/assets/downloads/tomtom-sdks/license.txt' }
  s.author           = 'TomTom N.V.'
  s.source           = {
    :http => 'https://repositories.tomtom.com/artifactory/cocoapods/TomTomSDKMapDisplay/0.74.0/TomTomSDKMapDisplay.tar.gz',
    :sha256 => 'ce893bf5dd7179d60faa9cfb930f358e23ca176dad751e6b7909601fdfe39daf',
  }

  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
  s.ios.frameworks = ['Foundation', 'UIKit', 'CoreLocation', 'GLKit', 'MetalKit', 'Combine', 'CoreGraphics', 'QuartzCore']
  s.vendored_frameworks = 'TomTomSDKMapDisplay.xcframework'

  s.ios.dependency 'TomTomSDKCommon', '0.74.0'
  s.ios.dependency 'TomTomSDKFeatureToggle', '0.74.0'
  s.ios.dependency 'TomTomSDKLocationProvider', '0.74.0'
  s.ios.dependency 'TomTomSDKBindingMapDisplayEngineInternal', '0.74.0'
  s.ios.dependency 'TomTomSDKMapTileStoreCommon', '0.74.0'
  s.ios.dependency 'TomTomSDKTelemetry', '0.74.0'
end
