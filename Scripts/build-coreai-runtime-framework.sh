#!/bin/sh
set -eu

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
RUNTIME_DIR="$ROOT_DIR/Runtime/CoreAIRuntime"
VERIFY_SCRIPT="$ROOT_DIR/Scripts/verify-coreai-runtime-framework.sh"
FRAMEWORK_NAME="AICoreKitCoreAIRuntime"

OUTPUT_DIR="${1:-}"
CONFIGURATION_NAME="${2:-${CONFIGURATION:-Debug}}"
PLATFORM="${3:-${PLATFORM_NAME:-iphoneos}}"

if [ -z "$OUTPUT_DIR" ]; then
  echo "Usage: $0 /path/to/output-dir [Debug|Release] [iphoneos|iphonesimulator]" >&2
  exit 64
fi

case "$PLATFORM" in
  iphoneos)
    DESTINATION="generic/platform=iOS"
    SDK="iphoneos"
    PRODUCTS_SUFFIX="iphoneos"
    ;;
  iphonesimulator)
    DESTINATION="generic/platform=iOS Simulator"
    SDK="iphonesimulator"
    PRODUCTS_SUFFIX="iphonesimulator"
    ;;
  *)
    echo "Unsupported Core AI runtime platform: $PLATFORM" >&2
    exit 65
    ;;
esac

if [ ! -f "$RUNTIME_DIR/Package.swift" ]; then
  echo "Core AI runtime package is missing: $RUNTIME_DIR" >&2
  exit 66
fi

mkdir -p "$OUTPUT_DIR"

DEST_FRAMEWORK="$OUTPUT_DIR/$FRAMEWORK_NAME.framework"
MARKER="$OUTPUT_DIR/.$FRAMEWORK_NAME.build-info"

REVISION=$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)
EXPECTED_MARKER="$REVISION|$CONFIGURATION_NAME|$PLATFORM"

if [ -f "$DEST_FRAMEWORK/$FRAMEWORK_NAME" ]; then
  if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$EXPECTED_MARKER" ]; then
    if "$VERIFY_SCRIPT" "$DEST_FRAMEWORK" >/dev/null 2>&1; then
      echo "Core AI runtime is already current: $DEST_FRAMEWORK"
      exit 0
    fi
  fi
fi

DERIVED_DATA="${AICOREKIT_RUNTIME_DERIVED_DATA:-}"
if [ -z "$DERIVED_DATA" ]; then
  BASE_TEMP="${TARGET_TEMP_DIR:-${TMPDIR:-/tmp}}"
  DERIVED_DATA="$BASE_TEMP/AICoreKitCoreAIRuntime-${PLATFORM}-${CONFIGURATION_NAME}"
fi

rm -rf "$DERIVED_DATA"

(
  cd "$RUNTIME_DIR"
  xcodebuild -scheme "$FRAMEWORK_NAME" -configuration "$CONFIGURATION_NAME" -destination "$DESTINATION" -sdk "$SDK" -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
)

BUILT_FRAMEWORK="$DERIVED_DATA/Build/Products/${CONFIGURATION_NAME}-${PRODUCTS_SUFFIX}/PackageFrameworks/$FRAMEWORK_NAME.framework"

if [ ! -f "$BUILT_FRAMEWORK/$FRAMEWORK_NAME" ]; then
  echo "Built Core AI runtime framework was not found: $BUILT_FRAMEWORK" >&2
  exit 67
fi

"$VERIFY_SCRIPT" "$BUILT_FRAMEWORK"

rm -rf "$DEST_FRAMEWORK"
ditto "$BUILT_FRAMEWORK" "$DEST_FRAMEWORK"
printf '%s' "$EXPECTED_MARKER" > "$MARKER"

echo "Core AI runtime ready: $DEST_FRAMEWORK"
