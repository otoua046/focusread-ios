#!/bin/zsh
set -euo pipefail

CONFIGURATION="${1:-Debug}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17 Pro Max}"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RESULT_DIR="$ROOT_DIR/benchmarks/results"
DERIVED_DATA="$ROOT_DIR/DerivedData"
STAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RESULT_BUNDLE="$RESULT_DIR/xctest-${CONFIGURATION}-${STAMP}.xcresult"

mkdir -p "$RESULT_DIR"

if [[ -z "${SIMULATOR_ID:-}" ]]; then
  SIMULATOR_ID="$(xcrun simctl list devices available | awk -v name="$SIMULATOR_NAME" '
    index($0, name) && match($0, /\([0-9A-F-]{36}\)/) {
      print substr($0, RSTART + 1, RLENGTH - 2)
      exit
    }
  ')"
fi

if [[ -z "$SIMULATOR_ID" ]]; then
  echo "Unable to find an available simulator named '$SIMULATOR_NAME'. Set SIMULATOR_ID or SIMULATOR_NAME." >&2
  exit 2
fi

xcodebuild test \
  -project "$ROOT_DIR/FocusRead.xcodeproj" \
  -scheme FocusRead \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_TESTABILITY=YES \
  -only-testing:FocusReadTests/ReaderPerformanceTests \
  -only-testing:FocusReadTests/ImportPipelinePerformanceTests \
  -only-testing:FocusReadTests/LibraryScalePerformanceTests \
  -only-testing:FocusReadTests/DiscoverPerformanceTests \
  -only-testing:FocusReadTests/OCRImportPerformanceTests

"$ROOT_DIR/benchmarks/scripts/extract-xcresult-metrics.js" "$RESULT_BUNDLE" \
  > "$RESULT_DIR/xctest-${CONFIGURATION}-${STAMP}-metrics.txt"

echo "Result bundle: $RESULT_BUNDLE"
echo "Metrics: $RESULT_DIR/xctest-${CONFIGURATION}-${STAMP}-metrics.txt"
