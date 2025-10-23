#!/bin/bash
# ==========================================================
# Moodle Patch Exporter
# Generates .patch file with all local changes to Moodle
# for integration into Docker /patches directory.
# ==========================================================

set -e

source .env 2>/dev/null || true

MOODLE_CONTAINER="${MOODLE_CONTAINER:-moodle}"
MOODLE_DIR="/var/www/html"
WORKDIR="$(pwd)"
PATCHES_DIR="${PATCHES_DIR:-$WORKDIR/patches}"
BACKUP_DIR="${BACKUP_DIR:-$WORKDIR/backups}"
PATCH_NAME="moodle-patch-$(hostname)-$(date +%Y%m%d-%H%M%S).patch"
BASE_DIR="$PATCHES_DIR/base"
BASE_ARCHIVE="$BASE_DIR/base.tar.gz"
CURRENT_ARCHIVE="$PATCHES_DIR/moodle-current.tar.gz"

echo "=== Moodle Patch Exporter ==="
echo "Target Moodle container: $MOODLE_CONTAINER"

if docker ps --format '{{.Names}}' | grep -wq "$MOODLE_CONTAINER"; then
  echo "📦 The Moodle container is used:$MOODLE_CONTAINER"
  echo "Creating an archive of the current state of Moodle from the container..."
  docker exec "$MOODLE_CONTAINER" tar -czf - -C /var/www/html . > "$CURRENT_ARCHIVE"
else
  echo "⚠️ Container not found, using local directory: $MOODLE_DIR"
  echo "Creating an archive of the current state of Moodle from a local directory..."
  tar -czf "$CURRENT_ARCHIVE" -C "$MOODLE_DIR" .
fi

echo "Output file: $PATCHES_DIR/$PATCH_NAME"
echo

# Ensure patches directories exist
mkdir -p "$PATCHES_DIR" "$BASE_DIR" "$BACKUP_DIR"

if [ -f "$BASE_ARCHIVE" ]; then
  # Extract both archives to temporary directories for diff
  TMP_BASE_DIR=$(mktemp -d)
  TMP_CURRENT_DIR=$(mktemp -d)

  tar -xzf "$BASE_ARCHIVE" -C "$TMP_BASE_DIR"
  tar -xzf "$CURRENT_ARCHIVE" -C "$TMP_CURRENT_DIR"

  # Generate diff patch
  diff -ruN "$TMP_BASE_DIR" "$TMP_CURRENT_DIR" > "$PATCHES_DIR/$PATCH_NAME" || true

  rm -rf "$TMP_BASE_DIR" "$TMP_CURRENT_DIR"

  if [ -s "$PATCHES_DIR/$PATCH_NAME" ]; then
    echo "✅ Patch created and saved to $PATCHES_DIR/$PATCH_NAME"
  else
    echo "ℹ️ No differences found."
    rm "$PATCHES_DIR/$PATCH_NAME"
  fi
else
  cp "$CURRENT_ARCHIVE" "$BASE_ARCHIVE"
  echo "ℹ️ Base snapshot created for future comparisons."
fi

echo
echo "To include this patch in Docker build:"
echo "  scp $PATCHES_DIR/$PATCH_NAME your-local-machine:./Docker/patches/"
echo "Then rebuild the Docker image."
echo "=========================================================="