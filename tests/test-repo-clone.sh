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
echo "=== --list Flag ==="

# --list shows menu and exits
output=$("$REPO_ROOT/repo-clone.sh" --list "$FIXTURES/catalog-valid.txt" 2>&1)
assert_contains "--list shows infra category" "[infra]" "$output"
assert_contains "--list shows libs category" "[libs]" "$output"
assert_contains "--list shows Build Pipeline" "Build Pipeline" "$output"
assert_contains "--list shows Common Utils" "Common Utils" "$output"
assert_contains "--list shows branch info" "(branch: staging)" "$output"

echo ""
echo "=== --repos Flag ==="

# --repos with valid name + dry-run
output=$("$REPO_ROOT/repo-clone.sh" --dry-run --repos "Build Pipeline" "$FIXTURES/catalog-valid.txt" 2>&1)
assert_contains "--repos selects correct repo" "Build Pipeline" "$output"
assert_contains "--repos dry-run works" "[dry-run]" "$output"

# --repos with multiple names + dry-run
output=$("$REPO_ROOT/repo-clone.sh" --dry-run --repos "Build Pipeline,Common Utils" "$FIXTURES/catalog-valid.txt" 2>&1)
assert_contains "--repos multi selects first" "Build Pipeline" "$output"
assert_contains "--repos multi selects second" "Common Utils" "$output"

# --repos with invalid name
output=$("$REPO_ROOT/repo-clone.sh" --repos "Nonexistent Repo" "$FIXTURES/catalog-valid.txt" 2>&1) || true
assert_contains "--repos invalid name shows error" "Error: No repo found matching name" "$output"

# --repos by number + dry-run
output=$("$REPO_ROOT/repo-clone.sh" --dry-run --repos "1" "$FIXTURES/catalog-valid.txt" 2>&1)
assert_contains "--repos by number selects correct repo" "Build Pipeline" "$output"

# --repos by multiple numbers + dry-run
output=$("$REPO_ROOT/repo-clone.sh" --dry-run --repos "1,3" "$FIXTURES/catalog-valid.txt" 2>&1)
assert_contains "--repos multi numbers selects first" "Build Pipeline" "$output"
assert_contains "--repos multi numbers selects third" "Common Utils" "$output"

# --repos mix of numbers and names + dry-run
output=$("$REPO_ROOT/repo-clone.sh" --dry-run --repos "1,Common Utils" "$FIXTURES/catalog-valid.txt" 2>&1)
assert_contains "--repos mixed selects by number" "Build Pipeline" "$output"
assert_contains "--repos mixed selects by name" "Common Utils" "$output"

# --repos invalid number (out of range)
output=$("$REPO_ROOT/repo-clone.sh" --repos "99" "$FIXTURES/catalog-valid.txt" 2>&1) || true
assert_contains "--repos invalid number shows error" "Error: Invalid repo number" "$output"

# --repos without value
output=$("$REPO_ROOT/repo-clone.sh" --repos 2>&1) || true
assert_contains "--repos without value shows error" "Error:" "$output"

echo ""
echo "=== --group Flag ==="

# --group with valid group + dry-run
output=$("$REPO_ROOT/repo-clone.sh" --dry-run --group "infra" "$FIXTURES/catalog-valid.txt" 2>&1)
assert_contains "--group selects first infra repo" "Build Pipeline" "$output"
assert_contains "--group selects second infra repo" "Deploy Tool" "$output"

# --group with single-entry group + dry-run
output=$("$REPO_ROOT/repo-clone.sh" --dry-run --group "libs" "$FIXTURES/catalog-valid.txt" 2>&1)
assert_contains "--group libs selects Common Utils" "Common Utils" "$output"

# --group with multiple groups + dry-run
output=$("$REPO_ROOT/repo-clone.sh" --dry-run --group "infra,libs" "$FIXTURES/catalog-valid.txt" 2>&1)
assert_contains "--group multi selects infra" "Build Pipeline" "$output"
assert_contains "--group multi selects libs" "Common Utils" "$output"

# --group with invalid group
output=$("$REPO_ROOT/repo-clone.sh" --group "nonexistent" "$FIXTURES/catalog-valid.txt" 2>&1) || true
assert_contains "--group invalid shows error" "Error: No group found matching" "$output"

# --group without value
output=$("$REPO_ROOT/repo-clone.sh" --group 2>&1) || true
assert_contains "--group without value shows error" "Error:" "$output"

echo ""
echo "=== Flags Anywhere ==="

# --list at end of args
output=$("$REPO_ROOT/repo-clone.sh" "$FIXTURES/catalog-valid.txt" --list 2>&1)
assert_contains "--list at end shows menu" "Build Pipeline" "$output"

# --dry-run after catalog source with --repos
output=$("$REPO_ROOT/repo-clone.sh" --repos "1" "$FIXTURES/catalog-valid.txt" --dry-run 2>&1)
assert_contains "--dry-run at end works" "[dry-run]" "$output"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
