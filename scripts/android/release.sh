#!/usr/bin/env bash
set -euo pipefail

required=(
  ANDROID_PACKAGE_NAME
  ANDROID_VERSION_NAME
  ANDROID_VERSION_CODE
  ANDROID_KEYSTORE_BASE64
  ANDROID_KEYSTORE_PASSWORD
  ANDROID_KEY_ALIAS
  ANDROID_KEY_PASSWORD
  ANDROID_PLAY_SERVICE_ACCOUNT_JSON_BASE64
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required value: $name" >&2
    exit 1
  fi
done

[[ "$ANDROID_PACKAGE_NAME" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]] || {
  echo "ANDROID_PACKAGE_NAME must be a valid lowercase application ID." >&2
  exit 1
}
[[ "$ANDROID_VERSION_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "ANDROID_VERSION_NAME must use X.Y.Z format." >&2
  exit 1
}
[[ "$ANDROID_VERSION_CODE" =~ ^[1-9][0-9]*$ ]] || {
  echo "ANDROID_VERSION_CODE must be a positive integer." >&2
  exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/himatch-android-release.XXXXXX")"
keystore_path="$work_dir/upload.jks"
service_account_path="$work_dir/play-service-account.json"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode > "$keystore_path"
printf '%s' "$ANDROID_PLAY_SERVICE_ACCOUNT_JSON_BASE64" | base64 --decode > "$service_account_path"
chmod 600 "$keystore_path" "$service_account_path"

keytool -list \
  -keystore "$keystore_path" \
  -storepass "$ANDROID_KEYSTORE_PASSWORD" \
  -alias "$ANDROID_KEY_ALIAS" >/dev/null

export ANDROID_KEYSTORE_PATH="$keystore_path"
cd "$repo_root/apps/android"
./gradlew --no-daemon --stacktrace bundleRelease

aab_path="$repo_root/apps/android/app/build/outputs/bundle/release/app-release.aab"
[[ -s "$aab_path" ]] || {
  echo "Signed Android App Bundle was not generated: $aab_path" >&2
  exit 1
}

node "$repo_root/scripts/android/upload-play.mjs" \
  --credentials "$service_account_path" \
  --package "$ANDROID_PACKAGE_NAME" \
  --bundle "$aab_path" \
  --track internal \
  --release-name "$ANDROID_VERSION_NAME ($ANDROID_VERSION_CODE)"

artifact_dir="${RUNNER_TEMP:-/tmp}/himatch-android-export"
mkdir -p "$artifact_dir"
cp "$aab_path" "$artifact_dir/Himatch-${ANDROID_VERSION_NAME}-${ANDROID_VERSION_CODE}.aab"
