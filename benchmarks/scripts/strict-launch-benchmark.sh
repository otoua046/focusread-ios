#!/bin/zsh
set -euo pipefail

CONFIGURATION="${1:-Debug}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17 Pro Max}"
BUNDLE_ID="${BUNDLE_ID:-com.otoua046.app}"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RESULT_DIR="$ROOT_DIR/benchmarks/results"
DERIVED_DATA="$ROOT_DIR/DerivedData"
STAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
LOG_FILE="$RESULT_DIR/strict-launch-${CONFIGURATION}-${STAMP}.tsv"

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

xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b

xcodebuild build \
  -project "$ROOT_DIR/FocusRead.xcodeproj" \
  -scheme FocusRead \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO

APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphonesimulator/FocusRead.app"

launch_once() {
  local label="$1"
  local started ended elapsed
  started="$(python3 - <<'PY'
import time
print(time.time())
PY
)"
  SIMCTL_CHILD_FOCUSREAD_SKIP_ONBOARDING=1 \
  SIMCTL_CHILD_FOCUSREAD_BENCHMARK_SIGNPOSTS=1 \
  xcrun simctl launch \
    --terminate-running-process \
    "$SIMULATOR_ID" \
    "$BUNDLE_ID" \
    -FocusReadBenchmarks \
    >/dev/null
  ended="$(python3 - <<'PY'
import time
print(time.time())
PY
)"
  elapsed="$(python3 - <<PY
print(round(float("$ended") - float("$started"), 4))
PY
)"
  printf "%s\t%s\n" "$label" "$elapsed" | tee -a "$LOG_FILE"
}

{
  echo "scenario\tseconds"
} > "$LOG_FILE"

xcrun simctl uninstall "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
launch_once "true-cold-clean-install"

xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
launch_once "cold-existing-data"

launch_once "warm-terminate-running-process"

xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
sleep 2
launch_once "after-force-quit"

echo "Launch log: $LOG_FILE"
