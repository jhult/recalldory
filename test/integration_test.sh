set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RECALLDORY="${RECALLDORY:-$SCRIPT_DIR/../build/release/recalldory}"
RECALLDORY="$(cd "$(dirname "$RECALLDORY")" && pwd)/$(basename "$RECALLDORY")"

if [ ! -x "$RECALLDORY" ]; then
  echo "ERROR: recalldory binary not found or not executable: $RECALLDORY" >&2
  echo "Build it first (e.g. inko build --release src/recalldory.inko) or set RECALLDORY." >&2
  exit 1
fi

PASS=0
FAIL=0
TEST_DIR=$(mktemp -d)

# Isolate HOME so hook registration and the global database never touch the
# developer's real ~/.claude or ~/.recalldory.
export HOME="$TEST_DIR/home"
mkdir -p "$HOME"
cd "$TEST_DIR"

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

assert_contains() {
  local label="$1" output="$2" expected="$3"
  if echo "$output" | grep -qF "$expected"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  expected to contain: $expected"
    echo "  got: $output"
  fi
}

assert_not_contains() {
  local label="$1" output="$2" unexpected="$3"
  if echo "$output" | grep -qF "$unexpected"; then
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  expected NOT to contain: $unexpected"
    echo "  got: $output"
  else
    PASS=$((PASS + 1))
  fi
}

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  expected: $expected"
    echo "  got: $actual"
  fi
}

# Extract the first numeric "id" value from a JSON output string.
extract_id() {
  echo "$1" | sed 's/.*"id": \([0-9]*\).*/\1/'
}

out=$("$RECALLDORY" add "Use snake_case for Python functions" --tags "python,style")
assert_contains "add returns success" "$out" '"success": true'
assert_contains "add returns id" "$out" '"id":'
mem_id=$(extract_id "$out")

out=$("$RECALLDORY" recall "snake_case Python")
assert_contains "recall finds memory" "$out" "snake_case"
assert_contains "recall returns results array" "$out" '"results":'
assert_not_contains "recall has no budget_remaining" "$out" "budget_remaining"

out=$("$RECALLDORY" list)
assert_contains "list returns results" "$out" "snake_case"

out=$("$RECALLDORY" add "Use snake_case for Python functions" --tags "python,style")
assert_contains "duplicate returns success" "$out" '"success": true'

out=$("$RECALLDORY" pin "$mem_id")
assert_contains "pin returns success" "$out" '"success": true'

out=$("$RECALLDORY" list --status pinned)
assert_contains "pinned memory in list" "$out" "snake_case"

out=$("$RECALLDORY" unpin "$mem_id")
assert_contains "unpin returns success" "$out" '"success": true'

out=$("$RECALLDORY" feedback "$mem_id" helpful)
assert_contains "helpful feedback succeeds" "$out" '"success": true'

out=$("$RECALLDORY" feedback "$mem_id" harmful)
assert_contains "harmful feedback succeeds" "$out" '"success": true'

out=$("$RECALLDORY" feedback "$mem_id" invalid 2>&1 || true)
assert_contains "invalid feedback type rejected" "$out" "Invalid feedback type"

out=$("$RECALLDORY" add "Original rule about testing" --tags "testing")
assert_contains "add original" "$out" '"success": true'

original_id=$(extract_id "$out")

out=$("$RECALLDORY" update "$original_id" "Updated rule about testing" --tags "testing")
assert_contains "update creates new version" "$out" '"success": true'
assert_contains "update returns new_id" "$out" '"new_id":'

out=$("$RECALLDORY" recall "testing")
assert_contains "recall finds updated version" "$out" "Updated rule"
assert_not_contains "recall excludes superseded" "$out" "Original rule"

out=$("$RECALLDORY" history "$original_id")
assert_contains "history returns versions" "$out" '"versions":'

out=$("$RECALLDORY" stats)
assert_contains "stats returns total" "$out" '"total":'
assert_contains "stats returns active" "$out" '"active":'

out=$("$RECALLDORY" export)
assert_contains "export returns memories" "$out" '"memories":'
assert_contains "export has exported_at" "$out" '"exported_at":'
assert_not_contains "export timestamp is not literal SQL" "$out" "datetime('now')"

out=$("$RECALLDORY" pin "$mem_id")
AGENTS_DIR="$TEST_DIR/agents_output"
mkdir -p "$AGENTS_DIR"
out=$("$RECALLDORY" agents-md --path "$AGENTS_DIR")
assert_contains "agents-md returns success" "$out" '"success": true'
if [ -f "$AGENTS_DIR/AGENTS.md" ]; then
  PASS=$((PASS + 1))
  agents_content=$(cat "$AGENTS_DIR/AGENTS.md")
  assert_contains "AGENTS.md has header" "$agents_content" "# recalldory Memories"
  assert_contains "AGENTS.md has pinned section" "$agents_content" "## Pinned Memories"
else
  FAIL=$((FAIL + 1))
  echo "FAIL: AGENTS.md file not created"
fi

out=$("$RECALLDORY" maintain --dry-run)
assert_contains "maintain dry-run returns stats" "$out" '"decayed":'

out=$("$RECALLDORY" maintain)
assert_contains "maintain returns stats" "$out" '"decayed":'

out=$("$RECALLDORY" contradictions)
assert_contains "contradictions returns array" "$out" '"contradictions":'

out=$("$RECALLDORY" rebuild-fts)
assert_contains "rebuild-fts succeeds" "$out" '"success": true'
assert_contains "rebuild-fts reports indexed" "$out" '"indexed":'

out=$("$RECALLDORY" add "Temporary memory to delete" --tags "temp")
temp_id=$(extract_id "$out")
out=$("$RECALLDORY" forget "$temp_id")
assert_contains "forget returns success" "$out" '"success": true'
out=$("$RECALLDORY" recall "Temporary memory delete" 2>&1 || true)
assert_not_contains "deleted memory not in recall" "$out" "Temporary memory to delete"

cat > "$TEST_DIR/import_test.json" <<'JSONEOF'
{"memories": [{"content": "Imported memory one", "tags": "import", "scope": "project"}, {"content": "Imported memory two", "tags": "import", "scope": "project"}]}
JSONEOF
out=$("$RECALLDORY" import "$TEST_DIR/import_test.json")
assert_contains "import returns success" "$out" '"success": true'
assert_contains "import count" "$out" '"imported": 2'

# --- global scope ---
out=$("$RECALLDORY" add "Global scoped memory" --scope global)
assert_contains "global add succeeds" "$out" '"success": true'
out=$("$RECALLDORY" list --scope global)
assert_contains "global list finds memory" "$out" "Global scoped memory"

# --- init ---
INIT_DIR="$TEST_DIR/init_test"
mkdir -p "$INIT_DIR"
out=$(cd "$INIT_DIR" && "$RECALLDORY" init)
assert_contains "init returns success" "$out" '"success": true'
if [ -f "$INIT_DIR/.gitignore" ] && grep -qF "/.recalldory/" "$INIT_DIR/.gitignore"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: init did not add /.recalldory/ to .gitignore"
fi

INIT2_DIR="$TEST_DIR/init2_test"
mkdir -p "$INIT2_DIR"
out=$(cd "$INIT2_DIR" && "$RECALLDORY" init --no-gitignore)
assert_contains "init --no-gitignore skips gitignore" "$out" "Skipped .gitignore"
if [ -f "$INIT2_DIR/.gitignore" ]; then
  FAIL=$((FAIL + 1))
  echo "FAIL: init --no-gitignore should not create .gitignore"
else
  PASS=$((PASS + 1))
fi

# --- hooks ---
out=$("$RECALLDORY" hook register)
assert_contains "hook register succeeds" "$out" '"success": true'
if grep -qF "hook inject" "$HOME/.claude/settings.json"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: hook register did not write the hook"
fi

out=$("$RECALLDORY" hook inject)
assert_contains "hook inject emits hook output" "$out" '"hookSpecificOutput"'

out=$("$RECALLDORY" hook unregister)
assert_contains "hook unregister succeeds" "$out" '"success": true'
if grep -qF "hook inject" "$HOME/.claude/settings.json"; then
  FAIL=$((FAIL + 1))
  echo "FAIL: hook unregister left the hook behind"
else
  PASS=$((PASS + 1))
fi

# --- invalid input exits non-zero ---
if "$RECALLDORY" bogus-command >/dev/null 2>&1; then
  FAIL=$((FAIL + 1))
  echo "FAIL: unknown command should exit non-zero"
else
  PASS=$((PASS + 1))
fi

out=$("$RECALLDORY" 2>&1 || true)
assert_contains "no command shows help" "$out" 'Usage: recalldory'

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
