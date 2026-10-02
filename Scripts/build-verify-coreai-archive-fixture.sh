#!/bin/sh
set -eu

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
FRAMEWORK_PATH="${1:-}"
FRAMEWORK_NAME="AICoreKitCoreAIRuntime"
HOST_MIN_IOS="${HOST_MIN_IOS:-26.0}"

if [ -z "$FRAMEWORK_PATH" ]; then
  echo "Usage: $0 /path/to/AICoreKitCoreAIRuntime.framework" >&2
  exit 64
fi

if [ ! -f "$FRAMEWORK_PATH/$FRAMEWORK_NAME" ]; then
  echo "Runtime framework not found: $FRAMEWORK_PATH" >&2
  exit 66
fi

FIXTURE_DIR="$ROOT_DIR/CompatibilityLab/ArchiveFixture"
PREBUILT_DIR="$FIXTURE_DIR/Prebuilt"
PROJECT="$FIXTURE_DIR/ArchiveFixture.xcodeproj"
SCHEME="ArchiveFixture"

WORK_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$WORK_DIR"
  rm -rf "$PREBUILT_DIR"
}
trap cleanup EXIT

mkdir -p "$PREBUILT_DIR"
ditto "$FRAMEWORK_PATH" "$PREBUILT_DIR/$FRAMEWORK_NAME.framework"

ARCHIVE_PATH="$WORK_DIR/ArchiveFixture.xcarchive"
DERIVED_DATA="$WORK_DIR/DerivedData"

xcodebuild   -project "$PROJECT"   -scheme "$SCHEME"   -configuration Release   -destination 'generic/platform=iOS'   -sdk iphoneos   -archivePath "$ARCHIVE_PATH"   -derivedDataPath "$DERIVED_DATA"   CODE_SIGNING_ALLOWED=NO   CODE_SIGNING_REQUIRED=NO   archive

APP_PATH="$ARCHIVE_PATH/Products/Applications/ArchiveFixture.app"
APP_BIN="$APP_PATH/ArchiveFixture"
EMBEDDED_FRAMEWORK="$APP_PATH/Frameworks/$FRAMEWORK_NAME.framework"
FRAMEWORK_BIN="$EMBEDDED_FRAMEWORK/$FRAMEWORK_NAME"

for path in   "$APP_PATH/Info.plist"   "$APP_BIN"   "$EMBEDDED_FRAMEWORK/Info.plist"   "$FRAMEWORK_BIN"
do
  if [ ! -e "$path" ]; then
    echo "Archive fixture output missing: $path" >&2
    exit 1
  fi
done

APP_MIN=$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$APP_PATH/Info.plist")
FRAMEWORK_MIN=$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$EMBEDDED_FRAMEWORK/Info.plist")

[ "$APP_MIN" = "$HOST_MIN_IOS" ] || {
  echo "Archive app MinimumOSVersion must be $HOST_MIN_IOS (found: $APP_MIN)" >&2
  exit 1
}

case "$FRAMEWORK_MIN" in
  27|27.0|27.0.0) ;;
  *)
    echo "Embedded runtime MinimumOSVersion must be iOS 27 (found: $FRAMEWORK_MIN)" >&2
    exit 1
    ;;
esac

otool -l "$APP_BIN" > "$WORK_DIR/app-load-commands.txt"
otool -l "$FRAMEWORK_BIN" > "$WORK_DIR/framework-load-commands.txt"
nm -m "$APP_BIN" > "$WORK_DIR/app-symbols.txt"

EXPECTED_LOAD_NAME="@rpath/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME"

awk -v expected="$EXPECTED_LOAD_NAME" '
  $1 == "cmd" { weak = ($2 == "LC_LOAD_WEAK_DYLIB") }
  weak && $1 == "name" && $2 == expected { found = 1 }
  END { exit !found }
' "$WORK_DIR/app-load-commands.txt" || {
  echo "Archived app is missing LC_LOAD_WEAK_DYLIB for $EXPECTED_LOAD_NAME" >&2
  grep -B2 -A5 "$FRAMEWORK_NAME" "$WORK_DIR/app-load-commands.txt" >&2 || true
  exit 1
}

grep -A8 'LC_BUILD_VERSION' "$WORK_DIR/app-load-commands.txt" | grep -Eq "minos $HOST_MIN_IOS$" || {
  echo "Archived app binary minimum iOS is not $HOST_MIN_IOS" >&2
  grep -A8 'LC_BUILD_VERSION' "$WORK_DIR/app-load-commands.txt" >&2 || true
  exit 1
}

grep -A8 'LC_BUILD_VERSION' "$WORK_DIR/framework-load-commands.txt" | grep -Eq 'minos 27(\.0)?$' || {
  echo "Embedded runtime binary minimum iOS is not 27." >&2
  grep -A8 'LC_BUILD_VERSION' "$WORK_DIR/framework-load-commands.txt" >&2 || true
  exit 1
}

grep -q 'weak external _AICKCoreAIIsAvailable' "$WORK_DIR/app-symbols.txt" || {
  echo "Archived app does not contain the expected weak Core AI symbol reference." >&2
  grep 'AICKCoreAI' "$WORK_DIR/app-symbols.txt" >&2 || true
  exit 1
}

echo "=== Lower-Minimum App Archive Verification ==="
echo "Archive:            $ARCHIVE_PATH"
echo "App MinimumOS:      $APP_MIN"
echo "Runtime MinimumOS:  $FRAMEWORK_MIN"
echo "Weak load command:  OK"
echo "Weak ABI reference: OK"
