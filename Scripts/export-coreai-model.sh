#!/bin/sh
set -eu

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
WORK_DIR="${COREAI_WORK_DIR:-$ROOT_DIR/.coreai-models-work}"
COREAI_DIR="$WORK_DIR/coreai-models"
COREAI_REVISION="${COREAI_MODELS_REVISION:-3efa838ebf1a1e816ef4c17eb5022fe22cda2cb9}"
MODEL_ID="${COREAI_MODEL_ID:-Qwen/Qwen3-0.6B}"
PLATFORM="${COREAI_PLATFORM:-iOS}"
OUTPUT_ROOT="${COREAI_OUTPUT_ROOT:-$ROOT_DIR/Artifacts/CoreAI}"
OUTPUT_NAME="${COREAI_OUTPUT_NAME:-AICoreKitLocalModel}"
OUTPUT_DIR="$OUTPUT_ROOT/$OUTPUT_NAME"
MAX_CONTEXT_LENGTH="${COREAI_MAX_CONTEXT_LENGTH:-4096}"

fail() {
  echo "error: $*" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || fail "git not found"
command -v uv >/dev/null 2>&1 || fail "uv not found"

case "$PLATFORM" in
  iOS|macOS) ;;
  *) fail "COREAI_PLATFORM must be iOS or macOS" ;;
esac

if [ "$PLATFORM" = "iOS" ]; then
  command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild not found"
  XCODE_VERSION=$(xcodebuild -version | awk 'NR==1 {print $2}')
  XCODE_MAJOR=$(printf '%s' "$XCODE_VERSION" | cut -d. -f1)
  case "$XCODE_MAJOR" in
    ''|*[!0-9]*) fail "unexpected Xcode version: $XCODE_VERSION" ;;
  esac
  [ "$XCODE_MAJOR" -ge 27 ] || fail "Xcode 27 or later is required. Current: $XCODE_VERSION"
fi

mkdir -p "$WORK_DIR" "$OUTPUT_ROOT"

if [ ! -d "$COREAI_DIR/.git" ]; then
  git clone https://github.com/apple/coreai-models.git "$COREAI_DIR"
else
  git -C "$COREAI_DIR" fetch origin
fi

git -C "$COREAI_DIR" checkout --detach "$COREAI_REVISION"
ACTUAL_REVISION=$(git -C "$COREAI_DIR" rev-parse HEAD)
[ "$ACTUAL_REVISION" = "$COREAI_REVISION" ]   || fail "unexpected Core AI revision: $ACTUAL_REVISION"

rm -rf "$OUTPUT_DIR"

(
  cd "$COREAI_DIR"
  uv run coreai.llm.export     "$MODEL_ID"     --platform "$PLATFORM"     --max-context-length "$MAX_CONTEXT_LENGTH"     --output-dir "$OUTPUT_ROOT"     --output-name "$OUTPUT_NAME"
)

[ -d "$OUTPUT_DIR" ] || fail "expected export folder missing: $OUTPUT_DIR"
find "$OUTPUT_DIR" -name '*.aimodel' -print | grep -q .   || fail "no .aimodel found in $OUTPUT_DIR"

cat > "$OUTPUT_DIR/aicorekit-model-profile.json" <<EOF
{
  "model": "$MODEL_ID",
  "platform": "$PLATFORM",
  "contextLength": $MAX_CONTEXT_LENGTH,
  "coreAIRevision": "$COREAI_REVISION"
}
EOF

echo "Exported Core AI model resource:"
echo "$OUTPUT_DIR"
