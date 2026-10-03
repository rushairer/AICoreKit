#!/bin/sh
set -eu

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

usage() {
  cat >&2 <<'EOF'
Usage:
  provision-coreai-model.sh --destination PATH [options]

Options:
  --destination PATH     Host app/package resource directory. Required.
  --source PATH          Install an already exported Core AI model directory.
                         When omitted, AICoreKit exports the model first.
  --model-id ID          Source model identifier.
                         Default: Qwen/Qwen3-0.6B
  --platform PLATFORM    iOS or macOS. Default: iOS
  --output-name NAME     Export directory name.
                         Default: destination directory basename
  --output-root PATH     Export root.
                         Default: AICoreKit/Artifacts/CoreAI
  --max-context N        Core AI export context length. Default: 4096
  -h, --help             Show this help.

Environment equivalents remain supported:
  COREAI_MODEL_ID
  COREAI_PLATFORM
  COREAI_OUTPUT_NAME
  COREAI_OUTPUT_ROOT
  COREAI_MAX_CONTEXT_LENGTH
  COREAI_WORK_DIR
  COREAI_MODELS_REVISION
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

DEST_DIR=""
SOURCE_DIR=""
MODEL_ID="${COREAI_MODEL_ID:-Qwen/Qwen3-0.6B}"
PLATFORM="${COREAI_PLATFORM:-iOS}"
OUTPUT_NAME="${COREAI_OUTPUT_NAME:-}"
OUTPUT_ROOT="${COREAI_OUTPUT_ROOT:-$ROOT_DIR/Artifacts/CoreAI}"
MAX_CONTEXT_LENGTH="${COREAI_MAX_CONTEXT_LENGTH:-4096}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --destination)
      [ "$#" -ge 2 ] || fail "--destination requires a path"
      DEST_DIR=$2
      shift 2
      ;;
    --source)
      [ "$#" -ge 2 ] || fail "--source requires a path"
      SOURCE_DIR=$2
      shift 2
      ;;
    --model-id)
      [ "$#" -ge 2 ] || fail "--model-id requires a value"
      MODEL_ID=$2
      shift 2
      ;;
    --platform)
      [ "$#" -ge 2 ] || fail "--platform requires a value"
      PLATFORM=$2
      shift 2
      ;;
    --output-name)
      [ "$#" -ge 2 ] || fail "--output-name requires a value"
      OUTPUT_NAME=$2
      shift 2
      ;;
    --output-root)
      [ "$#" -ge 2 ] || fail "--output-root requires a path"
      OUTPUT_ROOT=$2
      shift 2
      ;;
    --max-context)
      [ "$#" -ge 2 ] || fail "--max-context requires a value"
      MAX_CONTEXT_LENGTH=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[ -n "$DEST_DIR" ] || {
  usage
  exit 64
}

case "$PLATFORM" in
  iOS|macOS) ;;
  *) fail "--platform must be iOS or macOS" ;;
esac

case "$MAX_CONTEXT_LENGTH" in
  ''|*[!0-9]*) fail "--max-context must be a positive integer" ;;
esac
[ "$MAX_CONTEXT_LENGTH" -gt 0 ] || fail "--max-context must be greater than zero"

if [ -z "$OUTPUT_NAME" ]; then
  OUTPUT_NAME=$(basename "$DEST_DIR")
fi

if [ -z "$SOURCE_DIR" ]; then
  COREAI_MODEL_ID="$MODEL_ID" \
  COREAI_PLATFORM="$PLATFORM" \
  COREAI_OUTPUT_NAME="$OUTPUT_NAME" \
  COREAI_OUTPUT_ROOT="$OUTPUT_ROOT" \
  COREAI_MAX_CONTEXT_LENGTH="$MAX_CONTEXT_LENGTH" \
    "$ROOT_DIR/Scripts/export-coreai-model.sh"

  SOURCE_DIR="$OUTPUT_ROOT/$OUTPUT_NAME"
fi

"$ROOT_DIR/Scripts/install-coreai-model-resource.sh" \
  "$SOURCE_DIR" \
  "$DEST_DIR"

find "$DEST_DIR" -name '*.aimodel' -print | grep -q . \
  || fail "installed resource contains no .aimodel: $DEST_DIR"

PROFILE="$DEST_DIR/aicorekit-model-profile.json"
if [ -f "$PROFILE" ]; then
  echo "Model profile:"
  echo "$PROFILE"
else
  echo "warning: aicorekit-model-profile.json was not found." >&2
  echo "warning: this is allowed for legacy exports, but new exports should preserve the profile." >&2
fi

cat <<EOF

Core AI model provisioning is complete.

Next host-app gates:
  1. Confirm the destination directory is copied into the app/package resources.
  2. Confirm AICoreKitCoreAIRuntime.framework is weak-linked and Embed & Sign is configured.
  3. Confirm the host resolves the installed directory through CoreAIDirectoryModelResourceProvider.
  4. Run a signed-device generation on a supported OS/device.
  5. Run cold-preparation and warm-launch validation before calling local AI production-ready.

A build that succeeds without a model resource proves only graceful degradation.
EOF
