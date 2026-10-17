#!/usr/bin/env bash
# run-tests.sh — test runner for Ollama Backup Deluxe.
# Usage: tests/run-tests.sh [--suite <name-substring>...] [--list]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUITES=(); LIST_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite) SUITES+=("$2"); shift 2 ;;
    --list)  LIST_ONLY=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

ALL_UNIT=(tests/unit/test-*.sh)
if [[ "$LIST_ONLY" == "1" ]]; then
  for s in "${ALL_UNIT[@]}"; do echo "${s%.sh}"; done
  echo "tests/webapp (node --test)"
  exit 0
fi

TOTAL_PASS=0; TOTAL_FAIL=0; FAILED_SUITES=()
run_suite() { # run_suite <path>
  local path="$1" name out rc
  name="$(basename "$path" .sh)"
  if (( ${#SUITES[@]} > 0 )); then
    local match=0
    for want in "${SUITES[@]}"; do [[ "$name" == *"$want"* ]] && match=1; done
    (( match == 1 )) || return 0
  fi
  printf '\n== %s ==\n' "$name"
  out="$(bash "$path" 2>&1)"; rc=$?
  printf '%s\n' "$out"
  local p f
  p="$(printf '%s' "$out" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '[0-9]+')"
  f="$(printf '%s' "$out" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '[0-9]+')"
  p="${p:-0}"; f="${f:-0}"
  TOTAL_PASS=$((TOTAL_PASS + p)); TOTAL_FAIL=$((TOTAL_FAIL + f))
  (( rc == 0 )) || FAILED_SUITES+=("$name")
}

mkdir -p tests/.tmp
for s in "${ALL_UNIT[@]}"; do run_suite "$s"; done

# webapp tests (node:test) — only when node is available and suite filter allows
RUN_WEBAPP=1
if (( ${#SUITES[@]} > 0 )); then
  RUN_WEBAPP=0
  for want in "${SUITES[@]}"; do [[ "webapp" == *"$want"* || "$want" == "webapp" ]] && RUN_WEBAPP=1; done
fi
if [[ "$RUN_WEBAPP" == "1" ]] && command -v node >/dev/null 2>&1; then
  printf '\n== test-webapp ==\n'
  out="$(cd "$ROOT" && node --test tests/webapp/server.test.js 2>&1)"; rc=$?
  printf '%s\n' "$out" | tail -20
  p="$(printf '%s' "$out" | grep -oE '(^# pass|[ℹ] pass) ?[0-9]+' | tail -1 | grep -oE '[0-9]+')"
  f="$(printf '%s' "$out" | grep -oE '(^# fail|[ℹ] fail) ?[0-9]+' | tail -1 | grep -oE '[0-9]+')"
  p="${p:-0}"; f="${f:-0}"
  TOTAL_PASS=$((TOTAL_PASS + p)); TOTAL_FAIL=$((TOTAL_FAIL + f))
  (( rc == 0 )) || FAILED_SUITES+=("webapp")
fi

printf '\n==============================\nTOTAL: %d passed, %d failed\n' "$TOTAL_PASS" "$TOTAL_FAIL"
if (( ${#FAILED_SUITES[@]} > 0 )); then
  printf 'FAILED SUITES: %s\n' "${FAILED_SUITES[*]}"; exit 1
fi
exit 0
