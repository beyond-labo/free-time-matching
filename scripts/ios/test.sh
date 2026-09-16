#!/bin/bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_PATH="$ROOT_DIR/apps/ios/Himatch.xcodeproj"
SCHEME="Himatch"
DERIVED_DATA="$(mktemp -d "${RUNNER_TEMP:-/tmp}/himatch-derived-data.XXXXXX")"
RESULT_BUNDLE="${RUNNER_TEMP:-/tmp}/HimatchTests.xcresult"

cleanup() {
  rm -rf "$DERIVED_DATA"
}
trap cleanup EXIT

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Xcode project not found: $PROJECT_PATH" >&2
  exit 1
fi

xcodebuild -version
python3 --version
openssl version
python3 -B -m unittest discover -s "$ROOT_DIR/scripts/ios/tests" -p 'test_*.py'

if [[ -n "${IOS_SIMULATOR_DESTINATION:-}" ]]; then
  destination="$IOS_SIMULATOR_DESTINATION"
else
  device_id="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {print $2; exit}')"
  if [[ -z "$device_id" ]]; then
    echo "No available iPhone Simulator was found." >&2
    exit 1
  fi
  destination="platform=iOS Simulator,id=$device_id"
fi

rm -rf "$RESULT_BUNDLE"
xcodebuild test \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "$destination" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  CODE_SIGNING_ALLOWED=NO
