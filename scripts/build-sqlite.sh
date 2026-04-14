#!/usr/bin/env bash
# Build SQLite static library using zig for cross-compilation.
#
# Usage: scripts/build-sqlite.sh <inko-target|zig-target>
#
# Examples:
#   scripts/build-sqlite.sh arm64-linux-gnu
#   scripts/build-sqlite.sh x86_64-linux-musl
#
# Downloads the SQLite amalgamation if not already present in lib/,
# then compiles sqlite3.o and creates libsqlite3.a for the target.
set -euo pipefail

SQLITE_VERSION="3530000"
SQLITE_YEAR="2026"
SQLITE_URL="https://www.sqlite.org/${SQLITE_YEAR}/sqlite-amalgamation-${SQLITE_VERSION}.zip"
SQLITE_FLAGS="-DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_JSON1"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_DIR/lib"

# Map Inko target triple to zig target triple
# https://docs.inko-lang.org/manual/latest/guides/cross-compilation/#target-triples
inko_to_zig() {
  case "$1" in
    amd64-linux-gnu)    echo "x86_64-linux-gnu" ;;
    arm64-linux-gnu)    echo "aarch64-linux-gnu" ;;
    amd64-linux-musl)   echo "x86_64-linux-musl" ;;
    arm64-linux-musl)   echo "aarch64-linux-musl" ;;
    amd64-mac-native)   echo "x86_64-macos-none" ;;
    arm64-mac-native)   echo "aarch64-macos-none" ;;
    *)                  echo "$1" ;;
  esac
}

TARGET="${1:?Usage: $0 <inko-target|zig-target>}"
ZIG_TARGET="$(inko_to_zig "$TARGET")"

echo "Building SQLite for $TARGET (zig target: $ZIG_TARGET)"

# Download and extract amalgamation if sqlite3.c is missing
if [ ! -f "$LIB_DIR/sqlite3.c" ]; then
  ZIP_FILE="$PROJECT_DIR/sqlite-amalgamation-${SQLITE_VERSION}.zip"
  echo "Downloading SQLite amalgamation..."
  curl -sL "$SQLITE_URL" -o "$ZIP_FILE"
  unzip -jo "$ZIP_FILE" -d "$LIB_DIR"
  rm "$ZIP_FILE"
fi

echo "Compiling sqlite3.o..."
zig cc -c "$LIB_DIR/sqlite3.c" $SQLITE_FLAGS -fno-sanitize=all -target "$ZIG_TARGET" -o "$LIB_DIR/sqlite3.o"

echo "Creating libsqlite3.a..."
zig ar rcs "$LIB_DIR/libsqlite3.a" "$LIB_DIR/sqlite3.o"

echo "Done. Built $LIB_DIR/libsqlite3.a for $ZIG_TARGET"