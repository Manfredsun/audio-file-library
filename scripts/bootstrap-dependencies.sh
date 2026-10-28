#!/bin/bash
# Restore the committed lock after XcodeGen. Network resolution is explicit.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="$ROOT/build/tools/bin:$PATH"
LOCKDIR="FoleyLibrary.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
if [ "${1:-}" = "--restore-lock" ]; then
  mkdir -p "$LOCKDIR"
  cp dependencies/Package.resolved "$LOCKDIR/Package.resolved"
  exit 0
fi
xcodebuild -version
command -v xcodegen >/dev/null || { echo "Please install XcodeGen first."; exit 1; }
if [ "${1:-}" = "--check-tools" ]; then exit 0; fi
xcodegen generate
xcodebuild -project FoleyLibrary.xcodeproj -scheme FoleyLibrary \
  -resolvePackageDependencies -onlyUsePackageVersionsFromResolvedFile
