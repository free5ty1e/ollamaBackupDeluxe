#!/usr/bin/env bash
# shellcheck disable=SC2015  # _pass/_fail are side-effect-only, safe with && ||
# test-backup.sh — end-to-end backup against a sandbox fixture tree.
SUITE_NAME="test-backup"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$HERE/tests/lib/assert.sh"
source "$HERE/scripts/common.sh"
source "$HERE/tests/lib/sandbox.sh"

obd_find_7zz || { echo "  SKIP (no 7zz available)"; exit 0; }
TMP="$HERE/tests/.tmp/test-backup.$$"
trap 'rm -rf "$TMP"' EXIT
make_fixture_tree "$TMP/fix" || { echo "fixture failed"; exit 1; }
sandbox_env "$TMP/fix"
export OBD_NO_QUIT=1
Z="$OBD_7ZZ"

# --- dry run: staging built, no archive ---
dry_out="$(bash "$HERE/scripts/backup.sh" --dest "$TMP" --name dryrun --dry-run 2>&1)"
assert_contains "$dry_out" "DRY RUN" "dry run announces itself"
[[ ! -f "$TMP/dryrun.7z" ]] && _pass "dry run creates no archive" || _fail "dry run creates no archive"

# --- real backup ---
run_out="$(bash "$HERE/scripts/backup.sh" --dest "$TMP" --name obdtest --yes 2>&1)"; rc=$?
assert_exit "$rc" "0" "backup.sh exits 0"
assert_contains "$run_out" "Backup complete" "backup reports completion"
assert_file_exists "$TMP/obdtest.7z" "archive exists"
assert_file_exists "$TMP/obdtest.7z.sha256" "sha256 sidecar exists"
assert_file_exists "$TMP/obdtest.manifest.txt" "manifest sidecar exists"

# --- sha256 correctness ---
expect="$(awk '{print $1}' "$TMP/obdtest.7z.sha256")"
assert_eq "$(sha256_file "$TMP/obdtest.7z")" "$expect" "sha256 sidecar matches archive"

# --- archive structure ---
listing="$("$Z" l -ba "$TMP/obdtest.7z" 2>/dev/null || true)"
assert_contains "$listing" "home/.ollama/config.json"          "archive: ollama config"
assert_contains "$listing" "home/.ollama/id_ed25519"           "archive: identity keys"
assert_contains "$listing" "home/.ollama/models/manifests/"    "archive: models manifests"
assert_contains "$listing" "home/.ollama/logs/server.log"      "archive: logs included by default"
assert_contains "$listing" "home/.pi/agent/bin/pi"             "archive: pi launcher"
assert_contains "$listing" "home/.pi/agent/install/releases/"  "archive: pi managed release"
assert_contains "$listing" "Applications/Ollama.app/Contents/Resources/ollama" "archive: app binary"
assert_contains "$listing" "app-support/Ollama/db.sqlite"      "archive: app-support db"
assert_contains "$listing" "brew/Cellar/node/"                 "archive: node cellar"
assert_contains "$listing" "brew/Cellar/icu4c@9/"              "archive: node dep formulae"
assert_contains "$listing" "restore-kit/7zz"                   "archive: embedded 7zz"
assert_contains "$listing" "restore-kit/restore.sh"            "archive: embedded restore script"
assert_contains "$listing" "project/scripts/backup.sh"         "archive: project copy"
assert_contains "$listing" "manifest.env"                      "archive: machine manifest"
assert_contains "$listing" "MANIFEST.txt"                      "archive: human manifest"
assert_not_contains "$listing" "home/.ollama/cache"            "archive: cache excluded"
assert_not_contains "$listing" "install/staging"               "archive: pi staging excluded"

# --- manifest values ---
menv="$("$Z" e -y -bso0 -ba -so "$TMP/obdtest.7z" manifest.env)"
assert_contains "$menv" 'OLLAMA_VERSION="0.99.0"' "manifest: ollama version"
assert_contains "$menv" 'PI_VERSION="1.2.3"'      "manifest: pi version"
assert_contains "$menv" 'NODE_VERSION="v9.9.9"'   "manifest: node version"
assert_contains "$menv" 'NODE_MODE="brew"'        "manifest: node mode"
assert_contains "$menv" 'MODELS_COUNT="3"'        "manifest: model count"
assert_contains "$menv" "ARCH=\"$(uname -m)\""    "manifest: arch"
assert_contains "$menv" 'EXCLUDE_MODELS="0"'      "manifest: models included flag"
assert_contains "$menv" 'OPT_NODE="../Cellar/node/9.9.9"' "manifest: brew opt symlink target"
assert_contains "$menv" 'OPT_ICU4C_9="../Cellar/icu4c@9/9"' "manifest: brew opt symlink target (sanitized key)"

# --- bin-entries capture ---
bin_entries="$("$Z" e -y -bso0 -ba -so "$TMP/obdtest.7z" brew/bin-entries.txt)"
assert_contains "$bin_entries" $'node\t../Cellar/node/9.9.9/bin/node' "bin-entries: node link captured"
assert_contains "$bin_entries" $'npm\t../lib/node_modules/npm/bin/npm-cli.js' "bin-entries: npm link captured"

# --- exclude-models variant ---
bash "$HERE/scripts/backup.sh" --dest "$TMP" --name nomodels --exclude-models --no-logs --yes >/dev/null 2>&1
m2="$("$Z" e -y -bso0 -ba -so "$TMP/nomodels.7z" manifest.env)"
assert_contains "$m2" 'EXCLUDE_MODELS="1"' "exclude-models: flag recorded"
l2="$("$Z" l -ba "$TMP/nomodels.7z" 2>/dev/null || true)"
assert_not_contains "$l2" "home/.ollama/models" "exclude-models: models omitted"
assert_contains    "$l2" "home/.ollama/config.json" "exclude-models: config still present"
assert_not_contains "$l2" "home/.ollama/logs" "no-logs: logs omitted"

# --- insufficient space guard (code-level check) ---
grep -q "Not enough free space" "$HERE/scripts/backup.sh" && _pass "space guard message exists" || _fail "space guard message exists"
grep -q "FREE_KB \* 110 / 100 < TOTAL_KB" "$HERE/scripts/backup.sh" && _pass "space guard arithmetic present" || _fail "space guard arithmetic present"

finish
