#!/usr/bin/env bash
# Downloads the TomTom Orbis Maps Display SDK xcframeworks (and transitive closure)
# from TomTom's public artifactory into Frameworks/, for the Package.swift binaryTargets.
#
# PODS is TomTomSDKMapDisplay's full dependency closure at the pinned version. TomTom
# publishes no resolver here, so the list is resolved by hand from each pod's podspec
# (`s.ios.dependency`) and must be re-checked when VER changes — 0.47 → 0.73 added
# MapTileStoreCommon / Telemetry / ElasticDataProviderInternal / Route / RoutingCommon.
set -euo pipefail
VER="${1:-0.73.1}"
BASE="https://repositories.tomtom.com/artifactory/cocoapods"
DIR="$(cd "$(dirname "$0")/.." && pwd)/Frameworks"
mkdir -p "$DIR" && cd "$DIR"
PODS=(TomTomSDKMapDisplay TomTomSDKCommon TomTomSDKFeatureToggle TomTomSDKLocationProvider \
      TomTomSDKBindingMapDisplayEngineInternal TomTomSDKBindingFrameworkLoggingInternal \
      TomTomSDKBindingMapDisplayElasticDataProviderInternal TomTomSDKMapTileStoreCommon \
      TomTomSDKTelemetry TomTomSDKRoute TomTomSDKRoutingCommon)
for pod in "${PODS[@]}"; do
  echo "Fetching $pod ($VER)..."
  curl -fsSL "$BASE/$pod/$VER/$pod.tar.gz" -o "$pod.tgz"
  tar xzf "$pod.tgz" && rm "$pod.tgz"
done
echo "Done. Frameworks in $DIR"
