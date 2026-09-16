#!/bin/bash
set -Eeuo pipefail

umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_PATH="$ROOT_DIR/apps/ios/Himatch.xcodeproj"
SCHEME="Himatch"
WORK_ROOT="$(mktemp -d "${RUNNER_TEMP:-/tmp}/himatch-release.XXXXXX")"
SECRETS_DIR="$WORK_ROOT/secrets"
ARCHIVE_PATH="${RUNNER_TEMP:-/tmp}/Himatch.xcarchive"
EXPORT_PATH="${RUNNER_TEMP:-/tmp}/himatch-export"
KEYCHAIN_PATH="$WORK_ROOT/app-signing.keychain-db"
PROFILE_INSTALL_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
API_KEY_DIR="$HOME/.appstoreconnect/private_keys"
INSTALLED_PROFILE=""
INSTALLED_API_KEY=""
KEYCHAIN_CREATED=0

cleanup() {
  set +e
  if [[ -n "$INSTALLED_PROFILE" ]]; then rm -f "$INSTALLED_PROFILE"; fi
  if [[ -n "$INSTALLED_API_KEY" ]]; then rm -f "$INSTALLED_API_KEY"; fi
  if [[ "$KEYCHAIN_CREATED" -eq 1 ]]; then security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1; fi
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

required=(
  APPLE_TEAM_ID
  IOS_BUNDLE_ID
  IOS_MARKETING_VERSION
  IOS_BUILD_NUMBER
  IOS_DISTRIBUTION_CERTIFICATE_BASE64
  IOS_DISTRIBUTION_CERTIFICATE_PASSWORD
  IOS_PROVISIONING_PROFILE_BASE64
  APP_STORE_CONNECT_KEY_ID
  APP_STORE_CONNECT_ISSUER_ID
  APP_STORE_CONNECT_PRIVATE_KEY_BASE64
)

for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Required environment variable is missing: $name" >&2
    exit 1
  fi
done

if [[ ! "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "APPLE_TEAM_ID must be a 10-character Apple Team ID." >&2
  exit 1
fi
if [[ ! "$IOS_BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+$ ]]; then
  echo "IOS_BUNDLE_ID is not a valid explicit bundle identifier." >&2
  exit 1
fi
if [[ ! "$IOS_MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "IOS_MARKETING_VERSION must use X.Y.Z format." >&2
  exit 1
fi
if [[ ! "$IOS_BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "IOS_BUILD_NUMBER must contain one to three dot-separated integers." >&2
  exit 1
fi
if [[ ! "$APP_STORE_CONNECT_KEY_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "APP_STORE_CONNECT_KEY_ID must be a 10-character key ID." >&2
  exit 1
fi
if [[ ! "$APP_STORE_CONNECT_ISSUER_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "APP_STORE_CONNECT_ISSUER_ID must be a UUID." >&2
  exit 1
fi

mkdir -p "$SECRETS_DIR" "$PROFILE_INSTALL_DIR" "$API_KEY_DIR" "$EXPORT_PATH"

certificate_path="$SECRETS_DIR/distribution.p12"
profile_path="$SECRETS_DIR/distribution.mobileprovision"
profile_plist="$SECRETS_DIR/profile.plist"
certificate_pem="$SECRETS_DIR/distribution-certificate.pem"
certificate_der="$SECRETS_DIR/distribution-certificate.der"
private_key_pem="$SECRETS_DIR/distribution-private-key.pem"
api_private_key="$SECRETS_DIR/AuthKey.p8"
export_plist="$WORK_ROOT/ExportOptions.plist"

printf '%s' "$IOS_DISTRIBUTION_CERTIFICATE_BASE64" | base64 -D > "$certificate_path"
printf '%s' "$IOS_PROVISIONING_PROFILE_BASE64" | base64 -D > "$profile_path"
printf '%s' "$APP_STORE_CONNECT_PRIVATE_KEY_BASE64" | base64 -D > "$api_private_key"

security cms -D -i "$profile_path" > "$profile_plist"
openssl pkcs12 \
  -in "$certificate_path" \
  -clcerts \
  -nokeys \
  -passin env:IOS_DISTRIBUTION_CERTIFICATE_PASSWORD \
  -out "$certificate_pem"
openssl pkcs12 \
  -in "$certificate_path" \
  -nocerts \
  -nodes \
  -passin env:IOS_DISTRIBUTION_CERTIFICATE_PASSWORD \
  -out "$private_key_pem"
openssl x509 -in "$certificate_pem" -outform DER -out "$certificate_der"

python3 -B "$ROOT_DIR/scripts/ios/validate_signing_assets.py" \
  --profile-plist "$profile_plist" \
  --certificate-der "$certificate_der" \
  --certificate-pem "$certificate_pem" \
  --distribution-private-key "$private_key_pem" \
  --api-private-key "$api_private_key" \
  --team-id "$APPLE_TEAM_ID" \
  --bundle-id "$IOS_BUNDLE_ID"

profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$profile_plist")"
profile_name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$profile_plist")"

if [[ ! "$profile_uuid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
  echo "Provisioning profile UUID is invalid." >&2
  exit 1
fi
if [[ -z "$profile_name" || "$profile_name" == *$'\n'* || "$profile_name" == *$'\r'* ]]; then
  echo "Provisioning profile name contains unsupported characters." >&2
  exit 1
fi

INSTALLED_PROFILE="$PROFILE_INSTALL_DIR/$profile_uuid.mobileprovision"
cp "$profile_path" "$INSTALLED_PROFILE"

keychain_password="$(openssl rand -hex 24)"
security create-keychain -p "$keychain_password" "$KEYCHAIN_PATH"
KEYCHAIN_CREATED=1
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$keychain_password" "$KEYCHAIN_PATH"
security import "$certificate_path" \
  -k "$KEYCHAIN_PATH" \
  -P "$IOS_DISTRIBUTION_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$KEYCHAIN_PATH" >/dev/null
security list-keychains -d user -s "$KEYCHAIN_PATH"

plutil -create xml1 "$export_plist"
plutil -insert method -string app-store-connect "$export_plist"
plutil -insert destination -string export "$export_plist"
plutil -insert signingStyle -string manual "$export_plist"
plutil -insert signingCertificate -string "Apple Distribution" "$export_plist"
plutil -insert teamID -string "$APPLE_TEAM_ID" "$export_plist"
plutil -insert manageAppVersionAndBuildNumber -bool NO "$export_plist"
plutil -insert stripSwiftSymbols -bool YES "$export_plist"
plutil -insert provisioningProfiles -xml '<dict/>' "$export_plist"
/usr/libexec/PlistBuddy -c "Add :provisioningProfiles:$IOS_BUNDLE_ID string \"$profile_name\"" "$export_plist"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"
xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='Apple Distribution' \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$IOS_BUNDLE_ID" \
  PROVISIONING_PROFILE_SPECIFIER="$profile_name" \
  MARKETING_VERSION="$IOS_MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$IOS_BUILD_NUMBER"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$export_plist"

ipa_path="$(find "$EXPORT_PATH" -maxdepth 1 -name '*.ipa' -type f -print -quit)"
if [[ -z "$ipa_path" ]]; then
  echo "The archive was exported, but no IPA was produced." >&2
  exit 1
fi

INSTALLED_API_KEY="$API_KEY_DIR/AuthKey_$APP_STORE_CONNECT_KEY_ID.p8"
cp "$api_private_key" "$INSTALLED_API_KEY"

xcrun altool --validate-app \
  --file "$ipa_path" \
  --type ios \
  --apiKey "$APP_STORE_CONNECT_KEY_ID" \
  --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
xcrun altool --upload-app \
  --file "$ipa_path" \
  --type ios \
  --apiKey "$APP_STORE_CONNECT_KEY_ID" \
  --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"

echo "Uploaded $(basename "$ipa_path") to App Store Connect."
