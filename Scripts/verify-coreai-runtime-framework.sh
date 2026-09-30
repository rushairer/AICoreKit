#!/bin/sh
set -eu

FRAMEWORK_PATH="${1:-}"
FRAMEWORK_NAME="${2:-AICoreKitCoreAIRuntime}"

if [ -z "$FRAMEWORK_PATH" ]; then
  echo "Usage: $0 /path/to/AICoreKitCoreAIRuntime.framework [framework-name]" >&2
  exit 64
fi

FRAMEWORK_BIN="$FRAMEWORK_PATH/$FRAMEWORK_NAME"
EXPECTED_INSTALL_NAME="@rpath/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME"

if [ ! -f "$FRAMEWORK_BIN" ]; then
  echo "Runtime framework binary not found: $FRAMEWORK_BIN" >&2
  exit 66
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

otool -D "$FRAMEWORK_BIN" > "$WORK_DIR/install-name.txt"
otool -l "$FRAMEWORK_BIN" > "$WORK_DIR/load-commands.txt"
nm -gU "$FRAMEWORK_BIN" > "$WORK_DIR/exported-symbols.txt"

grep -Fxq "$EXPECTED_INSTALL_NAME" "$WORK_DIR/install-name.txt" || {
  echo "Unexpected framework install name." >&2
  cat "$WORK_DIR/install-name.txt" >&2
  exit 1
}

grep -A8 'LC_BUILD_VERSION' "$WORK_DIR/load-commands.txt" | grep -Eq 'minos 27(\.0)?$' || {
  echo "Runtime framework is not marked with an iOS 27 minimum deployment target." >&2
  grep -A8 'LC_BUILD_VERSION' "$WORK_DIR/load-commands.txt" >&2 || true
  exit 1
}

for symbol in \
  _AICKCoreAIIsAvailable \
  _AICKCoreAIGenerate \
  _AICKCoreAIPrepare \
  _AICKCoreAIUnload
do
  grep -Eq "[[:space:]]T[[:space:]]+$symbol$" "$WORK_DIR/exported-symbols.txt" || {
    echo "Missing exported C ABI symbol: $symbol" >&2
    exit 1
  }
done

echo "=== Core AI Runtime Framework Verification ==="
echo "Framework:          $FRAMEWORK_PATH"
echo "Install name:       $EXPECTED_INSTALL_NAME"
echo "Minimum iOS:        27"
echo "C ABI exports:      OK"
