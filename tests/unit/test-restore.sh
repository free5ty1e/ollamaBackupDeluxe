#!/usr/bin/env bash
# shellcheck disable=SC2015  # _pass/_fail are side-effect-only; A&&B||C is safe here
# test-restore.sh — end-to-end restore into an OBD_DEST_PREFIX sandbox.
# Destination contract (prefix mode): <prefix> + <original absolute path>.
SUITE_NAME="test-restore"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$HERE/tests/lib/assert.sh"
source "$HERE/scripts/common.sh"
source "$HERE/tests/lib/sandbox.sh"

obd_find_7zz || { echo "  SKIP (no 7zz available)"; exit 0; }
TMP="$HERE/tests/.tmp/test-restore.$$"
trap 'rm -rf "$TMP"' EXIT
make_fixture_tree "$TMP/fix"
FIX="$(cd "$TMP/fix" && pwd -P)"
sandbox_env "$FIX"
export OBD_NO_QUIT=1
Z="$OBD_7ZZ"

# --- build the kit ---
bash "$HERE/scripts/backup.sh" --dest "$TMP" --name kit --yes >/dev/null 2>&1 \
  || { echo "backup failed"; exit 1; }
ARCHIVE="$TMP/kit.7z"

# --- restore into prefix sandbox ---
export OBD_DEST_PREFIX="$TMP/dest"
out="$(bash "$HERE/scripts/restore.sh" --archive "$ARCHIVE" --yes 2>&1)"; rc=$?
assert_exit "$rc" "0" "restore.sh exits 0"
assert_contains "$out" "Restore complete" "restore reports completion"

# expected destinations: <prefix> + <fixture absolute path> (or known roots)
D="$TMP/dest"
APPD="$D$FIX/Applications/Ollama.app"
OHOMED="$D$FIX/fake-home/.ollama"
PID="$D$FIX/fake-home/.pi"
ASD="$D$FIX/fake-home/Library/Application Support/Ollama"
BREW="$D$FIX/brew"

assert_file_exists "$APPD/Contents/Resources/ollama" "app bundle restored"
assert_file_exists "$OHOMED/config.json" "ollama home restored"
assert_file_exists "$OHOMED/models/manifests/registry.ollama.ai/library/testmodel/1.0" "models manifests restored"
assert_file_exists "$OHOMED/models/blobs/sha256-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "model blobs restored"
assert_file_exists "$PID/agent/install/releases/1.2.3/node_modules/.bin/pi" "pi managed release restored"
assert_file_exists "$ASD/db.sqlite" "app-support restored"
assert_file_exists "$BREW/Cellar/node/9.9.9/bin/node" "node cellar restored"
assert_file_exists "$BREW/Cellar/icu4c@9/9/lib/libicuuc.9.dylib" "node dep cellar restored"

# --- symlinks recreated ---
assert_symlink_target "$D/usr/local/bin/ollama" "$APPD/Contents/Resources/ollama" "ollama CLI symlink"
assert_symlink_target "$D$FIX/fake-home/.local/bin/pi" "../../.pi/agent/bin/pi" "pi launcher symlink"
assert_symlink_target "$BREW/opt/node" "../Cellar/node/9.9.9" "brew opt/node symlink"
assert_symlink_target "$BREW/bin/node" "../Cellar/node/9.9.9/bin/node" "brew bin/node symlink"
assert_symlink_target "$BREW/bin/npm" "../lib/node_modules/npm/bin/npm-cli.js" "brew bin/npm symlink"

# --- restored node actually runs ---
assert_eq "$("$BREW/Cellar/node/9.9.9/bin/node" --version)" "v9.9.9" "restored node executes"

# --- exclusions did not leak ---
[[ ! -e "$OHOMED/cache" ]] && _pass "cache not restored" || _fail "cache not restored"
[[ ! -e "$PID/agent/install/staging" ]] && _pass "pi staging not restored" || _fail "pi staging not restored"

# --- second restore: pre-existing targets renamed aside, not deleted ---
out2="$(bash "$HERE/scripts/restore.sh" --archive "$ARCHIVE" --yes 2>&1)"; rc2=$?
assert_exit "$rc2" "0" "second restore exits 0"
assert_contains "$out2" "Moving existing" "second restore renames existing aside"
# shellcheck disable=SC2012  # glob-counting aside dirs, names are controlled
assert_dir_exists "$APPD.pre-restore-"* "old app moved aside (glob)"
assert_dir_exists "$OHOMED.pre-restore-"* "old ollama home moved aside"
assert_dir_exists "$PID.pre-restore-"* "old pi home moved aside"
assert_file_exists "$APPD/Contents/Resources/ollama" "fresh app in place after second restore"

# --- purge mode ---
rc3=0
bash "$HERE/scripts/restore.sh" --archive "$ARCHIVE" --yes --purge-existing >/dev/null 2>&1 || rc3=$?
assert_exit "$rc3" "0" "purge-existing restore exits 0"
asides="$(find "$(dirname "$OHOMED")" -maxdepth 1 -name "$(basename "$OHOMED").pre-restore-*" | wc -l | tr -d ' ')"
assert_eq "$asides" "1" "purge mode: no new asides created, prior one remains"

# --- standalone verify against restored tree ---
mkdir -p "$TMP/m"
"$Z" e -y -bso0 -o"$TMP/m" "$ARCHIVE" manifest.env >/dev/null 2>&1
vout="$(OBD_OLLAMA_APP="$APPD" \
  OBD_OLLAMA_HOME="$OHOMED" \
  OBD_OLLAMA_APP_SUPPORT="$ASD" \
  OBD_PI_HOME="$PID" \
  OBD_PI_LAUNCHER="$D$FIX/fake-home/.local/bin/pi" \
  OBD_BREW_PREFIX="$BREW" \
  bash "$HERE/scripts/verify.sh" --manifest "$TMP/m/manifest.env" --skip-cli-symlink --allow-offline 2>&1)"; vrc=$?
assert_exit "$vrc" "0" "verify.sh passes on restored tree"
assert_contains "$vout" "all" "verify output sane"

# --- verify fails when a component is broken ---
rm -rf "$OHOMED/models"
rc4=0
OBD_OLLAMA_APP="$APPD" \
  OBD_OLLAMA_HOME="$OHOMED" \
  OBD_PI_HOME="$PID" \
  OBD_BREW_PREFIX="$BREW" \
  bash "$HERE/scripts/verify.sh" --manifest "$TMP/m/manifest.env" --skip-cli-symlink --allow-offline >/dev/null 2>&1 || rc4=$?
assert_exit "$rc4" "1" "verify.sh fails when models missing"

finish
