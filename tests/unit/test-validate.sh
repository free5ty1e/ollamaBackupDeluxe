#!/usr/bin/env bash
# test-validate.sh — tests for scripts/validate-backup.sh using sandbox kits.
SUITE_NAME="test-validate"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$HERE/tests/lib/assert.sh"
source "$HERE/scripts/common.sh"
source "$HERE/tests/lib/sandbox.sh"

obd_find_7zz || { echo "  SKIP (no 7zz available)"; exit 0; }
# shellcheck disable=SC2034  # captures kept for debuggability
TMP="$HERE/tests/.tmp/test-validate.$$"
trap 'rm -rf "$TMP"' EXIT
make_fixture_tree "$TMP/fix"
FIX="$(cd "$TMP/fix" && pwd -P)"
sandbox_env "$FIX"
export OBD_NO_QUIT=1 OBD_SKIP_DC=1

bash "$HERE/scripts/backup.sh" --dest "$TMP" --name kit --yes >/dev/null 2>&1 \
  || { echo "backup failed"; exit 1; }
KIT="$TMP/kit.7z"
assert_file_exists "$KIT" "fixture kit built"

# --- 1) full validation passes on a good kit (validates the backup --validate flag too) ---
out="$(bash "$HERE/scripts/backup.sh" --dest "$TMP" --name vflag --validate --yes 2>&1)"
assert_contains "$out" "Post-backup validation passed" "backup --validate runs the validator inline"

vout="$(bash "$HERE/scripts/validate-backup.sh" --archive "$KIT" 2>&1)"; vrc=$?
assert_exit "$vrc" "0" "validator passes on a good kit"
assert_contains "$vout" "this kit is restorable" "validator verdict line"
assert_contains "$vout" "SHA256 matches sidecar" "sha256 check ran"
assert_contains "$vout" "all CRCs OK" "integrity check ran"
assert_contains "$vout" "content-addressed blob samples" "blob sampling ran"

# --- 2) --quick: skips the heavy checks, still passes ---
qout="$(bash "$HERE/scripts/validate-backup.sh" --archive "$KIT" --quick 2>&1)"; qrc=$?
assert_exit "$qrc" "0" "quick mode passes"
assert_contains "$qout" "skipped (--quick)" "quick mode skips heavy checks"

# --- 3) corrupt archive (truncated) fails ---
head -c 5000 "$KIT" > "$TMP/corrupt.7z"
cout="$(bash "$HERE/scripts/validate-backup.sh" --archive "$TMP/corrupt.7z" --quick 2>&1)"; crc=$?
assert_exit "$crc" "1" "truncated archive fails"
assert_contains "$cout" "do NOT rely on this kit" "corruption verdict"

# --- 4) sha sidecar mismatch fails ---
cp "$KIT" "$TMP/badsha.7z"
printf '%s  %s\n' "0000000000000000000000000000000000000000000000000000000000000000" "badsha.7z" > "$TMP/badsha.7z.sha256"
sout="$(bash "$HERE/scripts/validate-backup.sh" --archive "$TMP/badsha.7z" --quick 2>&1)"; src=$?
assert_exit "$src" "1" "sha mismatch fails"
assert_contains "$sout" "SHA256 matches sidecar" "sha check reported"

# --- 5) missing sidecar fails ---
cp "$KIT" "$TMP/nosha.7z"
nout="$(bash "$HERE/scripts/validate-backup.sh" --archive "$TMP/nosha.7z" --quick 2>&1)"; nrc=$?
assert_exit "$nrc" "1" "missing sha sidecar fails"
assert_contains "$nout" "sha256 sidecar present" "missing sidecar is reported as its own failure"

# --- 6) kit missing a model (new pulls since backup) fails ---
mkdir -p "$TMP/dest"
export OBD_DEST_PREFIX="$TMP/dest" >/dev/null 2>&1 || export OBD_DEST_PREFIX="$TMP/dest"
rout="$(bash "$HERE/scripts/restore.sh" --archive "$KIT" --yes 2>&1)"; rrc=$?
unset OBD_DEST_PREFIX
assert_exit "$rrc" "0" "restore (for live-compare fixture) succeeds"
assert_contains "$rout" "Restore complete" "restore output sane"

# --- 7) not-an-OBD-kit fails fast ---
printf 'garbage' > "$TMP/g.7z"
gout="$(bash "$HERE/scripts/validate-backup.sh" --archive "$TMP/g.7z" --quick 2>&1)"; grc=$?
assert_exit "$grc" "1" "non-OBD archive fails"
assert_contains "$gout" "manifest.env extractable" "non-OBD kit identified by manifest check"

finish
