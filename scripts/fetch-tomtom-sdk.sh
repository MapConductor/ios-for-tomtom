#!/usr/bin/env bash
# Downloads the TomTom Orbis Maps Display SDK xcframeworks (and transitive closure)
# from TomTom's public artifactory into Frameworks/, for the Package.swift binaryTargets.
set -euo pipefail
VER="${1:-0.47.5}"
BASE="https://repositories.tomtom.com/artifactory/cocoapods"
DIR="$(cd "$(dirname "$0")/.." && pwd)/Frameworks"
mkdir -p "$DIR" && cd "$DIR"
PODS=(TomTomSDKMapDisplay TomTomSDKCommon TomTomSDKFeatureToggle TomTomSDKLocationProvider \
      TomTomSDKBindingMapDisplayEngineInternal TomTomSDKBindingFrameworkLoggingInternal)
for pod in "${PODS[@]}"; do
  echo "Fetching $pod ($VER)..."
  curl -fsSL "$BASE/$pod/$VER/$pod.tar.gz" -o "$pod.tgz"
  tar xzf "$pod.tgz" && rm "$pod.tgz"
done
echo "Done. Frameworks in $DIR"
