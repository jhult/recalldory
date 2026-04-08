#!/usr/bin/env bash
# Integration tests for recalldory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RECALLDORY="${RECALLDORY:-$SCRIPT_DIR/../build/release/recalldory}"
RECALLDORY="$(cd "$(dirname "$RECALLDORY")" && pwd)/$(basename "$RECALLDORY")"
PASS=0
FAIL=0
TEST_DIR=$(mktemp -d)
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

# --- Test: basic add and recall ---
out=$("$RECALLDORY" add "Use snake_case for Python functions" --tags "python,style")
assert_contains "add returns success" "$out" '"success": true'
assert_contains "add returns id" "$out" '"id":'

# --- Test: recall finds the memory ---
out=$("$RECALLDORY" recall "snake_case Python")
assert_contains "recall finds memory" "$out" "snake_case"
assert_contains "recall returns results array" "$out" '"results":'
assert_not_contains "recall has no budget_remaining" "$out" "budget_remaining"

# --- Test: list ---
out=$("$RECALLDORY" list)
assert_contains "list returns results" "$out" "snake_case"

# --- Test: duplicate detection ---
out=$("$RECALLDORY" add "Use snake_case for Python functions" --tags "python,style")
assert_contains "duplicate returns success" "$out" '"success": true'
# Should return same id (duplicate detected)

# --- Test: pin/unpin ---
out=$("$RECALLDORY" pin 1)
assert_contains "pin returns success" "$out" '"success": true'

out=$("$RECALLDORY" list --status pinned)
assert_contains "pinned memory in list" "$out" "snake_case"

out=$("$RECALLDORY" unpin 1)
assert_contains "unpin returns success" "$out" '"success": true'

# --- Test: feedback validation ---
out=$("$RECALLDORY" feedback 1 helpful)
assert_contains "helpful feedback succeeds" "$out" '"success": true'

out=$("$RECALLDORY" feedback 1 harmful)
assert_contains "harmful feedback succeeds" "$out" '"success": true'

out=$("$RECALLDORY" feedback 1 invalid 2>&1 || true)
assert_contains "invalid feedback type rejected" "$out" "Invalid feedback type"

# --- Test: search excludes superseded memories ---
out=$("$RECALLDORY" add "Original rule about testing" --tags "testing")
assert_contains "add original" "$out" '"success": true'

# Get the id of the memory we just added
original_id=$(echo "$out" | sed 's/.*"id": \([0-9]*\).*/\1/')

out=$("$RECALLDORY" update "$original_id" "Updated rule about testing" --tags "testing")
assert_contains "update creates new version" "$out" '"success": true'
assert_contains "update returns new_id" "$out" '"new_id":'

# Search should only find the updated version, not the superseded one
out=$("$RECALLDORY" recall "testing")
assert_contains "recall finds updated version" "$out" "Updated rule"
assert_not_contains "recall excludes superseded" "$out" "Original rule"

# --- Test: history ---
new_id=$(echo "$out" | sed 's/.*"new_id": \([0-9]*\).*/\1/' | head -1)
# Use the update output to get the new_id
out=$("$RECALLDORY" update "$original_id" "Updated rule about testing" --tags "testing" 2>&1 || true)
# Just test history on id 1
out=$("$RECALLDORY" history 1)
assert_contains "history returns versions" "$out" '"versions":'

# --- Test: stats ---
out=$("$RECALLDORY" stats)
assert_contains "stats returns total" "$out" '"total":'
assert_contains "stats returns active" "$out" '"active":'

# --- Test: export ---
out=$("$RECALLDORY" export)
assert_contains "export returns memories" "$out" '"memories":'
assert_contains "export has exported_at" "$out" '"exported_at":'
assert_not_contains "export timestamp is not literal SQL" "$out" "datetime('now')"

# --- Test: agents-md writes file ---
out=$("$RECALLDORY" pin 1)
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

# --- Test: maintain ---
out=$("$RECALLDORY" maintain --dry-run)
assert_contains "maintain dry-run returns stats" "$out" '"decayed":'

out=$("$RECALLDORY" maintain)
assert_contains "maintain returns stats" "$out" '"decayed":'

# --- Test: contradictions ---
out=$("$RECALLDORY" contradictions)
assert_contains "contradictions returns array" "$out" '"contradictions":'

# --- Test: forget deletes memory and FTS ---
out=$("$RECALLDORY" add "Temporary memory to delete" --tags "temp")
temp_id=$(echo "$out" | sed 's/.*"id": \([0-9]*\).*/\1/')
out=$("$RECALLDORY" forget "$temp_id")
assert_contains "forget returns success" "$out" '"success": true'
# Should not appear in search
out=$("$RECALLDORY" recall "Temporary memory delete" 2>&1 || true)
assert_not_contains "deleted memory not in recall" "$out" "Temporary memory to delete"

# --- Test: import ---
cat > "$TEST_DIR/import_test.json" <<'JSONEOF'
{"memories": [{"content": "Imported memory one", "tags": "import", "scope": "project"}, {"content": "Imported memory two", "tags": "import", "scope": "project"}]}
JSONEOF
out=$("$RECALLDORY" import "$TEST_DIR/import_test.json")
assert_contains "import returns success" "$out" '"success": true'
assert_contains "import count" "$out" '"imported": 2'

# --- Test: no command ---
out=$("$RECALLDORY" 2>&1 || true)
assert_contains "no command shows help" "$out" 'Usage: recalldory'

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
