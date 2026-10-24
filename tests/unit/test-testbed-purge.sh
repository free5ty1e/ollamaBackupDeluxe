#!/usr/bin/env bash
# shellcheck disable=SC2015  # _pass/_fail are side-effect-only; A&&B||C is safe here
# test-testbed-purge.sh — the testbed purge script, run entirely against
# sandbox fixtures via OBD_* overrides. The REAL brew is never touched
# (the fixture prefix never matches `brew --prefix`).
SUITE_NAME="test-testbed-purge"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$HERE/tests/lib/assert.sh"
source "$HERE/scripts/common.sh"
source "$HERE/tests/lib/sandbox.sh"

TMP="$HERE/tests/.tmp/test-purge.$$"
trap 'rm -rf "$TMP"' EXIT
make_fixture_tree "$TMP/fix"
FIX="$(cd "$TMP/fix" && pwd -P)"
sandbox_env "$FIX"
export OBD_NO_QUIT=1 OBD_SKIP_DC=1

# extra purge targets that exist in the fixture
mkdir -p "$FIX/fake-home/.cache/opencode" "$FIX/fake-home/.local/state/opencode"
echo x > "$FIX/fake-home/.cache/opencode/c"
echo x > "$FIX/fake-home/.local/state/opencode/model.json"
echo x > "$FIX/fake-home/Library/Preferences/com.ollama.Ollama.plist" 2>/dev/null || true

# --- dry-run: nothing deleted ---
out="$(bash "$HERE/scripts/testbed-purge.sh" 2>&1)"
assert_contains "$out" "DRY RUN — nothing deleted" "dry-run announces itself"
assert_contains "$out" "Ollama data (MODELS)" "dry-run lists ollama data"
assert_dir_exists "$OBD_OLLAMA_HOME" "dry-run: ollama home still present"
assert_dir_exists "$OBD_PI_HOME" "dry-run: pi home still present"

# --- audit mode: reports everything ---
aout="$(bash "$HERE/scripts/testbed-purge.sh" --audit 2>&1)"
assert_contains "$aout" "OBD testbed audit" "audit header"
assert_contains "$aout" "Ollama app" "audit lists ollama app"
assert_contains "$aout" "0.40.3" "audit shows live versions from fixture"

# --- purge: everything the restore installs is gone ---
pout="$(printf 'PURGE\n' | bash "$HERE/scripts/testbed-purge.sh" --yes 2>&1)"; prc=$?
assert_exit "$prc" "0" "purge exits 0"
assert_contains "$pout" "removed Ollama app" "ollama app removed"
assert_contains "$pout" "removed Ollama data (MODELS)" "ollama data removed"
assert_contains "$pout" "removed Pi home" "pi home removed"
assert_contains "$pout" "removed Claude runtime" "claude runtime removed"
assert_contains "$pout" "removed OpenCode home" "opencode home removed"

[[ ! -e "$OBD_OLLAMA_APP" ]] && _pass "ollama app gone" || _fail "ollama app gone"
[[ ! -e "$OBD_OLLAMA_HOME" ]] && _pass "ollama data gone" || _fail "ollama data gone"
[[ ! -L "$OBD_OLLAMA_CLI" && ! -e "$OBD_OLLAMA_CLI" ]] && _pass "ollama cli gone" || _fail "ollama cli gone"
[[ ! -e "$OBD_OLLAMA_APP_SUPPORT" ]] && _pass "app support gone" || _fail "app support gone"
[[ ! -e "$OBD_PI_HOME" ]] && _pass "pi gone" || _fail "pi gone"
[[ ! -e "$OBD_PI_LAUNCHER" ]] && _pass "pi launcher gone" || _fail "pi launcher gone"
[[ ! -e "$OBD_CLAUDE_SHARE" ]] && _pass "claude runtime gone" || _fail "claude runtime gone"
[[ ! -e "$OBD_CLAUDE_HOME" ]] && _pass "claude data gone" || _fail "claude data gone"
[[ ! -e "$OBD_CLAUDE_LAUNCHER" ]] && _pass "claude launcher gone" || _fail "claude launcher gone"
[[ ! -e "$OBD_OPENCODE_HOME" ]] && _pass "opencode home gone" || _fail "opencode home gone"
[[ ! -e "$OBD_OPENCODE_CONFIG" ]] && _pass "opencode config gone" || _fail "opencode config gone"
[[ ! -e "$OBD_OPENCODE_SHARE" ]] && _pass "opencode sessions gone" || _fail "opencode sessions gone"
[[ ! -e "$OBD_OPENCODE_STATE" ]] && _pass "opencode state gone" || _fail "opencode state gone"
[[ ! -e "$OBD_HOME/.cache/opencode" ]] && _pass "opencode cache gone" || _fail "opencode cache gone"

# node chain: fixture prefix never matches real brew → direct Cellar removal
[[ ! -e "$OBD_BREW_PREFIX/Cellar/node" ]] && _pass "node cellar gone" || _fail "node cellar gone"
[[ ! -e "$OBD_BREW_PREFIX/lib/node_modules" ]] && _pass "node_modules gone" || _fail "node_modules gone"
[[ ! -e "$OBD_BREW_PREFIX/opt/node" ]] && _pass "node opt symlink gone" || _fail "node opt symlink gone"
[[ ! -e "$OBD_BREW_PREFIX/bin/node" ]] && _pass "brew bin node gone" || _fail "brew bin node gone"

# --- other things must survive ---
assert_dir_exists "$FIX/fake-home/.config/filezilla" "unrelated ~/.config apps survive"
assert_file_exists "$FIX/fake-home/.zshrc" "shell rc survives"
[[ -d "$OBD_BREW_PREFIX/Cellar/icu4c@9" ]] && _pass "node-dep formulae also purged (chain)" || _fail "node-dep formulae also purged (chain)"

# --- audit after purge: all absent ---
aout2="$(bash "$HERE/scripts/testbed-purge.sh" --audit 2>&1)"
assert_contains "$aout2" "ABSENT" "post-purge audit shows absent binaries"
assert_contains "$aout2" "absent" "post-purge audit shows absent paths"

finish
