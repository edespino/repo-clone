#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected to contain: $needle"
        echo "    actual: $haystack"
        FAIL=$((FAIL + 1))
    fi
}

assert_line_count() {
    local desc="$1" expected="$2" actual_output="$3"
    local count
    count=$(echo "$actual_output" | wc -l | xargs)
    if [[ "$expected" == "$count" ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected $expected lines, got $count"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Argument Parsing ==="

# --help
output=$("$REPO_ROOT/repo-clone.sh" --help 2>&1) || true
assert_contains "--help shows usage" "Usage:" "$output"

# --version
output=$("$REPO_ROOT/repo-clone.sh" --version 2>&1)
assert_contains "--version shows version" "repo-clone" "$output"

# No args
output=$("$REPO_ROOT/repo-clone.sh" 2>&1) || true
assert_contains "no args shows error" "Error:" "$output"

# Remote without path
output=$("$REPO_ROOT/repo-clone.sh" git@github.com:org/repo.git 2>&1) || true
assert_contains "remote without path shows error" "Error:" "$output"

echo ""
echo "=== Local Catalog Fetch ==="

# Nonexistent file
output=$("$REPO_ROOT/repo-clone.sh" ./nonexistent-file.txt 2>&1) || true
assert_contains "missing file shows error" "Error:" "$output"

echo ""
echo "=== Catalog Parsing ==="

# Valid catalog: 3 entries, 2 categories, 1 with branch
output=$("$REPO_ROOT/repo-clone.sh" --test-parse "$FIXTURES/catalog-valid.txt" 2>&1)
assert_line_count "valid catalog has 3 entries" "3" "$output"
assert_contains "first entry is infra category" "infra|Build Pipeline" "$output"
assert_contains "second entry has staging branch" "Deploy Tool|git@github.com:org/deploy-tool.git|staging" "$output"
assert_contains "third entry is libs category" "libs|Common Utils" "$output"

# Comments-only catalog with one entry
output=$("$REPO_ROOT/repo-clone.sh" --test-parse "$FIXTURES/catalog-comments.txt" 2>&1)
assert_line_count "comments catalog has 1 entry" "1" "$output"
assert_contains "entry is in tools category" "tools|My Tool" "$output"

# Empty catalog (only comments): should fail
output=$("$REPO_ROOT/repo-clone.sh" --test-parse "$FIXTURES/catalog-empty.txt" 2>&1) || true
assert_contains "empty catalog shows error" "Error:" "$output"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
