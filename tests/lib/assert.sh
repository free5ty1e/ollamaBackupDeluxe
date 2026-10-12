#!/usr/bin/env bash
# assert.sh — tiny zero-dependency assertion helpers for the OBD test suite.
# Usage: source tests/lib/assert.sh; then call asserts; end file with finish.

TEST_FAILS=0
TEST_PASSES=0

_pass() { TEST_PASSES=$((TEST_PASSES+1)); printf '  ok   %s\n' "$1"; }
_fail() {
  TEST_FAILS=$((TEST_FAILS+1))
  printf '  FAIL %s\n' "$1" >&2
  [[ -n "${2:-}" ]] && printf '       got: %s\n' "$2" >&2
}

assert_eq() { # <actual> <expected> <label>
  if [[ "$1" == "$2" ]]; then _pass "$3"; else _fail "$3 (expected '$2')" "$1"; fi
}
assert_contains() { # <haystack> <needle> <label>
  if [[ "$1" == *"$2"* ]]; then _pass "$3"; else _fail "$3 (should contain '$2')" "$1"; fi
}
assert_not_contains() {
  if [[ "$1" != *"$2"* ]]; then _pass "$3"; else _fail "$3 (should NOT contain '$2')" "$1"; fi
}
assert_file_exists() {
  if [[ -f "$1" ]]; then _pass "$2 ($1)"; else _fail "$2 (missing file $1)"; fi
}
assert_dir_exists() {
  if [[ -d "$1" ]]; then _pass "$2 ($1)"; else _fail "$2 (missing dir $1)"; fi
}
assert_symlink_target() { # <link> <expected-target> <label>
  local t; t="$(readlink "$1" 2>/dev/null || true)"
  if [[ "$t" == "$2" ]]; then _pass "$3"; else _fail "$3 (link target)" "${t:-<not a symlink>}"; fi
}
assert_exit() { # <rc> <expected-rc> <label>
  if [[ "$1" == "$2" ]]; then _pass "$3"; else _fail "$3 (expected exit $2)" "exit $1"; fi
}
assert_cmd_ok() { # <label> cmd...
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then _pass "$label"; else _fail "$label (command failed): $*"; fi
}

finish() { # prints suite summary and exits nonzero on failures
  printf '  ---- %s: %d passed, %d failed ----\n' "${SUITE_NAME:-suite}" "$TEST_PASSES" "$TEST_FAILS"
  (( TEST_FAILS == 0 )) || exit 1
  exit 0
}
