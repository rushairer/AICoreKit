#!/bin/sh
set -eu

ROOT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/aicorekit-model-provision.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

SOURCE_DIR="$TMP_DIR/source"
DEST_DIR="$TMP_DIR/destination"
mkdir -p "$SOURCE_DIR/nested" "$DEST_DIR"

printf "fixture\n" > "$SOURCE_DIR/nested/Test.aimodel"
cat > "$SOURCE_DIR/aicorekit-model-profile.json" <<'EOF'
{
  "model": "tests/fixture",
  "platform": "iOS",
  "contextLength": 128,
  "coreAIRevision": "fixture"
}
EOF

printf "keep me\n" > "$DEST_DIR/README.md"
printf "stale\n" > "$DEST_DIR/stale.txt"

"$ROOT_DIR/Scripts/provision-coreai-model.sh" \
  --source "$SOURCE_DIR" \
  --destination "$DEST_DIR"

[ -f "$DEST_DIR/nested/Test.aimodel" ]
[ -f "$DEST_DIR/aicorekit-model-profile.json" ]
[ -f "$DEST_DIR/README.md" ]
[ ! -e "$DEST_DIR/stale.txt" ]
grep -q "keep me" "$DEST_DIR/README.md"

echo "Local model provisioning fixture passed."
