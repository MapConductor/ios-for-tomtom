# TomTom Orbis Maps SDK の `TomTomSDKFeatureToggle` を CocoaPods から引くためだけの spec。
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
  s.name             = 'TomTomSDKFeatureToggle'
  s.version          = '0.74.0'
  s.summary          = 'TomTomSDKFeatureToggle'
  s.homepage         = 'https://developer.tomtom.com/'
  s.license          = { :type => 'Copyright', :text => 'Copyright 2022 TomTom N.V., https://developer.tomtom.com/assets/downloads/tomtom-sdks/license.txt' }
  s.author           = 'TomTom N.V.'
  s.source           = {
    :http => 'https://repositories.tomtom.com/artifactory/cocoapods/TomTomSDKFeatureToggle/0.74.0/TomTomSDKFeatureToggle.tar.gz',
    :sha256 => 'b35992d87cef4f2a8fa440296e395f425ff90ad8e36fdfc2c030eb12f5aa8299',
  }

  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
  s.ios.frameworks = ['Foundation']
  s.vendored_frameworks = 'TomTomSDKFeatureToggle.xcframework'

  s.ios.dependency 'TomTomSDKCommon', '0.74.0'
end
