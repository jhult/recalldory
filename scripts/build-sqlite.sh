set -euo pipefail

SQLITE_VERSION="3530400"
SQLITE_YEAR="2026"
SQLITE_URL="https://www.sqlite.org/${SQLITE_YEAR}/sqlite-amalgamation-${SQLITE_VERSION}.zip"
# SHA-256 of sqlite-amalgamation-${SQLITE_VERSION}.zip, pinned so a tampered or
# truncated download is rejected instead of being compiled into the binary.
SQLITE_SHA256="1e71ddf93849c6a6ecf58b827c0692073d2dd7ee40196158068f7b29f422e87d"
SQLITE_FLAGS="-O2 -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_JSON1"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_DIR/lib"

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

# Verify the SHA-256 of a file, using whichever tool is available.
verify_sha256() {
  local file="$1" expected="$2" actual

  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    echo "error: no sha256 tool found (need sha256sum or shasum)" >&2
    exit 1
  fi

  if [ "$actual" != "$expected" ]; then
    echo "error: checksum mismatch for $file" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi
}

TARGET="${1:?Usage: $0 <inko-target|zig-target>}"
ZIG_TARGET="$(inko_to_zig "$TARGET")"

echo "Building SQLite for $TARGET (zig target: $ZIG_TARGET)"

if [ ! -f "$LIB_DIR/sqlite3.c" ]; then
  ZIP_FILE="$PROJECT_DIR/sqlite-amalgamation-${SQLITE_VERSION}.zip"
  echo "Downloading SQLite amalgamation..."
  curl -fsSL "$SQLITE_URL" -o "$ZIP_FILE"
  verify_sha256 "$ZIP_FILE" "$SQLITE_SHA256"
  # Extract only sqlite3.c (junk the directory prefix) so no extra files land
  # in lib/. -f already makes curl fail on HTTP errors before unzip runs.
  unzip -jo "$ZIP_FILE" "*/sqlite3.c" -d "$LIB_DIR"
  rm "$ZIP_FILE"
fi

echo "Compiling sqlite3.o..."
zig cc -c "$LIB_DIR/sqlite3.c" $SQLITE_FLAGS -fno-sanitize=all -target "$ZIG_TARGET" -o "$LIB_DIR/sqlite3.o"

echo "Creating libsqlite3.a..."
zig ar rcs "$LIB_DIR/libsqlite3.a" "$LIB_DIR/sqlite3.o"

echo "Done. Built $LIB_DIR/libsqlite3.a for $ZIG_TARGET"
