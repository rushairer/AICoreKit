#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 /path/to/coreai-models [output-directory]" >&2
  exit 64
fi

COREAI_MODELS_DIR="$1"
OUTPUT_DIR=""
if [ "$#" -eq 2 ]; then
  OUTPUT_DIR="$2"
fi
MODEL_ID="${MODEL_ID:-Qwen/Qwen3-0.6B}"
MAX_CONTEXT_LENGTH="${MAX_CONTEXT_LENGTH:-4096}"

if [ ! -f "$COREAI_MODELS_DIR/pyproject.toml" ]; then
  echo "coreai-models checkout not found at: $COREAI_MODELS_DIR" >&2
  exit 66
fi

cd "$COREAI_MODELS_DIR"

args=(
  run
  coreai.llm.export
  "$MODEL_ID"
  --platform
  iOS
  --max-context-length
  "$MAX_CONTEXT_LENGTH"
)

if [ -n "$OUTPUT_DIR" ]; then
  args+=(--output-dir "$OUTPUT_DIR")
fi

uv "${args[@]}"
