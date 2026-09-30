#!/bin/sh
set -eu

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
FRAMEWORK_PATH="${1:-}"
HOST_MIN_IOS="${HOST_MIN_IOS:-17.0}"

if [ -z "$FRAMEWORK_PATH" ]; then
  echo "Usage: $0 /path/to/AICoreKitCoreAIRuntime.framework" >&2
  exit 64
fi

FRAMEWORK_DIR=$(dirname "$FRAMEWORK_PATH")
FRAMEWORK_NAME="AICoreKitCoreAIRuntime"
EXPECTED_LOAD_NAME="@rpath/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME"

if [ ! -f "$FRAMEWORK_PATH/$FRAMEWORK_NAME" ]; then
  echo "Runtime framework not found: $FRAMEWORK_PATH" >&2
  exit 66
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

HOST_BIN="$WORK_DIR/AICoreKitWeakHostFixture"
SDKROOT=$(xcrun --sdk iphoneos --show-sdk-path)

xcrun --sdk iphoneos clang \
  -arch arm64 \
  -isysroot "$SDKROOT" \
  -miphoneos-version-min="$HOST_MIN_IOS" \
  -I "$ROOT_DIR/Sources/AICoreWeakBridgeShim/include" \
  "$ROOT_DIR/CompatibilityLab/HostFixture/main.c" \
  "$ROOT_DIR/Sources/AICoreWeakBridgeShim/AICoreWeakBridgeShim.c" \
  -F "$FRAMEWORK_DIR" \
  -Wl,-rpath,@executable_path/Frameworks \
  -weak_framework "$FRAMEWORK_NAME" \
  -o "$HOST_BIN"

otool -l "$HOST_BIN" > "$WORK_DIR/load-commands.txt"
nm -m "$HOST_BIN" > "$WORK_DIR/symbols.txt"

awk -v expected="$EXPECTED_LOAD_NAME" '
  $1 == "cmd" { weak = ($2 == "LC_LOAD_WEAK_DYLIB") }
  weak && $1 == "name" && $2 == expected { found = 1 }
  END { exit !found }
' "$WORK_DIR/load-commands.txt" || {
  echo "Host fixture is missing LC_LOAD_WEAK_DYLIB for $EXPECTED_LOAD_NAME" >&2
  grep -B2 -A5 "$FRAMEWORK_NAME" "$WORK_DIR/load-commands.txt" >&2 || true
  exit 1
}

grep -A8 'LC_BUILD_VERSION' "$WORK_DIR/load-commands.txt" | grep -Eq "minos $HOST_MIN_IOS$" || {
  echo "Host fixture minimum iOS is not $HOST_MIN_IOS" >&2
  grep -A8 'LC_BUILD_VERSION' "$WORK_DIR/load-commands.txt" >&2 || true
  exit 1
}

grep -q 'weak external _AICKCoreAIIsAvailable' "$WORK_DIR/symbols.txt" || {
  echo "Host fixture does not contain the expected weak C ABI reference." >&2
  grep 'AICKCoreAI' "$WORK_DIR/symbols.txt" >&2 || true
  exit 1
}

echo "=== Lower-Minimum Host Weak-Link Verification ==="
echo "Host minimum iOS:   $HOST_MIN_IOS"
echo "Runtime minimum:    iOS 27+"
echo "Load command:       LC_LOAD_WEAK_DYLIB"
echo "Runtime install:    $EXPECTED_LOAD_NAME"
echo "Weak ABI reference: OK"
