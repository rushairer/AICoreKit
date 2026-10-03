#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 SOURCE_MODEL_DIRECTORY DESTINATION_DIRECTORY" >&2
  exit 64
fi

SOURCE_DIR=$1
DEST_DIR=$2

fail() {
  echo "error: $*" >&2
  exit 1
}

[ -d "$SOURCE_DIR" ] || fail "model source missing: $SOURCE_DIR"
find "$SOURCE_DIR" -name '*.aimodel' -print | grep -q .   || fail "no .aimodel found in $SOURCE_DIR"

mkdir -p "$DEST_DIR"

find "$DEST_DIR" -mindepth 1 \
  ! -name '.gitkeep' \
  ! -name '.gitignore' \
  ! -name 'README.md' \
  -exec rm -rf {} +

(
  cd "$SOURCE_DIR"
  tar -cf - .
) | (
  cd "$DEST_DIR"
  tar -xf -
)

find "$DEST_DIR" -name '*.aimodel' -print | grep -q .   || fail "model copy failed: $DEST_DIR"

echo "Installed Core AI model resource:"
echo "$DEST_DIR"
echo "Preserved host sentinels when present: .gitkeep, .gitignore, README.md"
