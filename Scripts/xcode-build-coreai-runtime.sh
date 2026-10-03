#!/bin/sh
set -eu

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

: "${BUILT_PRODUCTS_DIR:?BUILT_PRODUCTS_DIR is required}"
: "${CONFIGURATION:?CONFIGURATION is required}"
: "${PLATFORM_NAME:?PLATFORM_NAME is required}"

case "$PLATFORM_NAME" in
  iphoneos|iphonesimulator)
    ;;
  *)
    echo "Skipping Core AI runtime for unsupported host platform: $PLATFORM_NAME"
    exit 0
    ;;
esac

HOST_PROJECT="${PROJECT_NAME:-Host}"
HOST_TARGET="${TARGET_NAME:-Target}"
HOST_KEY=$(printf '%s-%s-%s-%s' "$HOST_PROJECT" "$HOST_TARGET" "$CONFIGURATION" "$PLATFORM_NAME" | tr -c 'A-Za-z0-9._-' '_')
RUNTIME_TEMP_ROOT="${TMPDIR:-/tmp}"
export AICOREKIT_RUNTIME_DERIVED_DATA="${AICOREKIT_RUNTIME_DERIVED_DATA:-${RUNTIME_TEMP_ROOT%/}/AICoreKitCoreAIRuntime-${HOST_KEY}}"

/bin/sh "$ROOT_DIR/Scripts/build-coreai-runtime-framework.sh" "$BUILT_PRODUCTS_DIR" "$CONFIGURATION" "$PLATFORM_NAME"
