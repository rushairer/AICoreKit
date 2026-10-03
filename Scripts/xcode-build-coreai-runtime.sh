#!/bin/sh
set -eu

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

: "${BUILT_PRODUCTS_DIR:?BUILT_PRODUCTS_DIR is required}"
: "${CONFIGURATION:?CONFIGURATION is required}"
: "${PLATFORM_NAME:?PLATFORM_NAME is required}"

export AICOREKIT_RUNTIME_DERIVED_DATA="${AICOREKIT_RUNTIME_DERIVED_DATA:-${TARGET_TEMP_DIR:-${TMPDIR:-/tmp}}/AICoreKitCoreAIRuntimeDerivedData}"

"$ROOT_DIR/Scripts/build-coreai-runtime-framework.sh" "$BUILT_PRODUCTS_DIR" "$CONFIGURATION" "$PLATFORM_NAME"
