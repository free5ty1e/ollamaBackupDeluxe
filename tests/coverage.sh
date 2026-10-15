#!/usr/bin/env bash
# coverage.sh — run the full test suite with coverage collection and produce a
# markdown report: per-suite results, bash line coverage (kcov, child processes
# included), and webapp JS coverage (node built-in --experimental-test-coverage).
#
# Output: coverage/coverage-report.md (+ coverage/cobertura.xml via kcov,
# coverage/node-coverage.txt). Also written to $GITHUB_STEP_SUMMARY when set.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT" || exit 1

COV_DIR="$ROOT/coverage"
KCOV_DIR="$COV_DIR/kcov"
LOG_DIR="$COV_DIR/logs"
mkdir -p "$KCOV_DIR" "$LOG_DIR"
rm -rf "${KCOV_DIR:?}"/* 2>/dev/null || true

command -v kcov >/dev/null 2>&1 || { echo "kcov is required (brew install kcov)" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1) bash suites under kcov (kcov accumulates runs in one dir; data includes
#    child scripts — backup.sh/restore.sh/… — via the PS4 trace method)
# ---------------------------------------------------------------------------
TOTAL_PASS=0; TOTAL_FAIL=0; FAILED_SUITES=()
SUITE_ROWS=""
for suite in tests/unit/test-*.sh; do
  name="$(basename "$suite" .sh)"
  log="$LOG_DIR/$name.log"
  kcov --include-path="$ROOT/scripts" --collect-only "$KCOV_DIR" "$suite" > "$log" 2>&1
  rc=$?
  p="$(grep -oE '[0-9]+ passed' "$log" | tail -1 | grep -oE '[0-9]+')"; p="${p:-0}"
  f="$(grep -oE '[0-9]+ failed' "$log" | tail -1 | grep -oE '[0-9]+')"; f="${f:-0}"
  TOTAL_PASS=$((TOTAL_PASS + p)); TOTAL_FAIL=$((TOTAL_FAIL + f))
  if (( rc != 0 )); then FAILED_SUITES+=("$name"); fi
  SUITE_ROWS+="| \`$name\` | $p | $f |"$'\n'
  printf '  %-20s %s passed, %s failed (rc=%s)\n' "$name" "$p" "$f" "$rc"
done

# merge the accumulated per-run dirs into one report
rm -rf "$KCOV_DIR/merged"
run_dirs=()
for d in "$KCOV_DIR"/test-*.sh.*; do [[ -d "$d" ]] && run_dirs+=("$d"); done
if (( ${#run_dirs[@]} > 0 )); then
  kcov --merge "$KCOV_DIR/merged" "${run_dirs[@]}" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# 2) webapp coverage (node built-in)
# ---------------------------------------------------------------------------
NODE_LOG="$COV_DIR/node-coverage.txt"
node --test --experimental-test-coverage tests/webapp/server.test.js > "$NODE_LOG" 2>&1
NODE_RC=$?
np="$(grep -oE '^# pass [0-9]+|^ℹ pass [0-9]+' "$NODE_LOG" | tail -1 | grep -oE '[0-9]+')"; np="${np:-0}"
nf="$(grep -oE '^# fail [0-9]+|^ℹ fail [0-9]+' "$NODE_LOG" | tail -1 | grep -oE '[0-9]+')"; nf="${nf:-0}"
TOTAL_PASS=$((TOTAL_PASS + np)); TOTAL_FAIL=$((TOTAL_FAIL + nf))
(( NODE_RC == 0 )) || FAILED_SUITES+=("webapp")
SUITE_ROWS+="| \`webapp (node:test)\` | $np | $nf |"$'\n'
printf '  %-20s %s passed, %s failed (rc=%s)\n' "webapp" "$np" "$nf" "$NODE_RC"

# ---------------------------------------------------------------------------
# 3) build the report
# ---------------------------------------------------------------------------
TS="$(date -u '+%Y-%m-%d %H:%M:%SZ')"
COVERED_LINES=0; TOTAL_LINES=0
BASH_ROWS=""
merged_json="$(find "$KCOV_DIR/merged" -name coverage.json 2>/dev/null | head -1)"
if [[ -n "$merged_json" ]]; then
  while IFS=$'\t' read -r file pct cl tl; do
    COVERED_LINES=$((COVERED_LINES + cl)); TOTAL_LINES=$((TOTAL_LINES + tl))
    BASH_ROWS+="| \`$file\` | ${pct}% | $cl / $tl |"$'\n'
  done < <(python3 - "$merged_json" "$ROOT" <<'PY'
import json, sys, os
d = json.load(open(sys.argv[1]))
root = sys.argv[2].rstrip("/") + "/"
for f in sorted(d.get("files", []), key=lambda x: x.get("percent_covered", 0)):
    path = f.get("file", "?")
    if path.startswith("./"): path = path[2:]
    if path.startswith(root): path = path[len(root):]
    print(f"{path}\t{float(f.get('percent_covered', 0)):.1f}\t{f.get('covered_lines', 0)}\t{f.get('total_lines', 0)}")
PY
  )
fi
if (( TOTAL_LINES > 0 )); then
  BASH_PCT="$(python3 -c "print(f'{$COVERED_LINES/$TOTAL_LINES*100:.1f}')")"
else
  BASH_PCT="n/a"
fi

NODE_TABLE="$(awk '/start of coverage/{flag=1} flag' "$NODE_LOG" 2>/dev/null | head -12 || true)"

REPORT="$COV_DIR/coverage-report.md"
{
  echo "# Ollama Backup Deluxe — coverage report"
  echo
  echo "_Generated $TS (CI: tests/coverage.sh — bash line coverage via kcov, JS via node:test coverage)_"
  echo
  echo "## Test suites"
  echo
  echo "| Suite | Passed | Failed |"
  echo "|---|---|---|"
  printf '%s' "$SUITE_ROWS"
  echo
  echo "**Total: $TOTAL_PASS passed, $TOTAL_FAIL failed** $([ ${#FAILED_SUITES[@]} -gt 0 ] && echo "— FAILED: ${FAILED_SUITES[*]}")"
  echo
  echo "## Bash line coverage (scripts/ — exercised by the test suites)"
  echo
  echo "| Script | Coverage | Lines covered |"
  echo "|---|---|---|"
  printf '%s' "$BASH_ROWS"
  echo
  echo "**Bash total: $BASH_PCT ($COVERED_LINES / $TOTAL_LINES lines)**"
  echo
  echo "## Web app coverage (node:test, server.js)"
  echo
  echo '```'
  printf '%s\n' "$NODE_TABLE"
  echo '```'
  echo
  echo "## Reading this report"
  echo
  echo "- Bash coverage counts **executable lines** in \`scripts/*.sh\` exercised anywhere in the"
  echo "  suite runs (kcov traces child processes, so \`backup.sh\`/\`restore.sh\` invoked by tests are included)."
  echo "- Uncovered lines are typically error/die branches, elevation fallbacks, and interactive prompts —"
  echo "  they are verified by the real-world runbooks instead (\`llm-wiki/runbooks/\`)."
  echo "- Raw data: \`coverage/kcov/merged\` (kcov JSON), \`coverage/node-coverage.txt\`, per-suite logs in \`coverage/logs/\`."
} > "$REPORT"

{
  echo "### Coverage — $TOTAL_PASS passed / $TOTAL_FAIL failed · bash $BASH_PCT"
  echo
  printf '%s' "$BASH_ROWS"
} > "${GITHUB_STEP_SUMMARY:-/dev/null}" 2>/dev/null || true

echo
echo "==============================================="
echo "Tests:   $TOTAL_PASS passed, $TOTAL_FAIL failed"
echo "Bash:    $BASH_PCT line coverage ($COVERED_LINES/$TOTAL_LINES)"
echo "Report:  $REPORT"
if (( ${#FAILED_SUITES[@]} > 0 )); then
  echo "FAILED SUITES: ${FAILED_SUITES[*]}"
  exit 1
fi
exit 0
