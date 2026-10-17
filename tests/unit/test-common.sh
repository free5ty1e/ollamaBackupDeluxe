#!/usr/bin/env bash
# test-common.sh — unit tests for scripts/common.sh helpers
SUITE_NAME="test-common"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$HERE/tests/lib/assert.sh"
source "$HERE/scripts/common.sh"
source "$HERE/tests/lib/sandbox.sh"

TMP="$HERE/tests/.tmp/test-common.$$"; mkdir -p "$TMP"

# --- obd_model_list (classic + v2 manifests, library + user namespaces) ---
make_fixture_tree "$TMP/fix"
out="$(obd_model_list "$TMP/fix/fake-home/.ollama")"
assert_contains "$out" "testmodel:1.0" "model list: library model"
assert_contains "$out" "user42/custom:3.1" "model list: user namespace model"
assert_contains "$out" "other:2.0" "model list: manifests-v2 model"
n="$(printf '%s\n' "$out" | grep -c .)"; assert_eq "$n" "3" "model list: exactly 3 models"
out_empty="$(obd_model_list "$TMP/nonexistent")"; assert_eq "$out_empty" "" "model list: missing home → empty"

# --- obd_dest prefix mapping (prefix + absolute path) ---
export OBD_DEST_PREFIX="$TMP/prefix"
assert_eq "$(obd_dest /Applications/Ollama.app)" "$TMP/prefix/Applications/Ollama.app" "dest map: /Applications"
assert_eq "$(obd_dest /usr/local/bin/ollama)"    "$TMP/prefix/usr/local/bin/ollama"    "dest map: /usr/local"
assert_eq "$(obd_dest /usr/local)"               "$TMP/prefix/usr/local"               "dest map: /usr/local bare"
assert_eq "$(obd_dest /opt/homebrew/Cellar/x)"   "$TMP/prefix/opt/homebrew/Cellar/x"   "dest map: /opt/homebrew"
assert_eq "$(obd_dest /private/tmp/arbitrary)"   "$TMP/prefix/private/tmp/arbitrary"   "dest map: arbitrary absolute"
unset OBD_DEST_PREFIX
assert_eq "$(obd_dest /Applications/Ollama.app)" "/Applications/Ollama.app" "dest map: no prefix → passthrough"

# --- human_size ---
assert_eq "$(human_size 0)" "0B" "human_size: 0"
assert_eq "$(human_size 512)" "512B" "human_size: bytes"
assert_eq "$(human_size 2048)" "2KB" "human_size: KB"
assert_eq "$(human_size 1048576)" "1MB" "human_size: MB"
assert_eq "$(human_size 1610612736)" "1GB" "human_size: GB"

# --- sanitized_key ---
assert_eq "$(sanitized_key "icu4c@78")" "ICU4C_78" "sanitized_key: @ handled"
assert_eq "$(sanitized_key "node")" "NODE" "sanitized_key: plain"

# --- obd_find_7zz priority (OBD_7ZZ env) ---
fake7="$TMP/fake-7zz"; printf '#!/bin/sh\nexit 0\n' > "$fake7"; chmod +x "$fake7"
OBD_7ZZ="$fake7"; export OBD_7ZZ
obd_find_7zz; assert_eq "$OBD_7ZZ" "$fake7" "find_7zz: env override wins"
unset OBD_7ZZ

# --- harness version detection (fixture binaries) ---
sandbox_env "$TMP/fix"
assert_eq "$(obd_detect_claude_version)" "2.1.251" "claude version via launcher symlink"
assert_eq "$(obd_detect_opencode_version)" "1.19.0" "opencode version via home binary"

# --- manifest.env round trip (quoted values with spaces) ---
cat > "$TMP/manifest.env" <<EOF
OLLAMA_HOME_PATH="$TMP/fix/fake-home/.ollama"
OLLAMA_APP_SUPPORT_PATH="$TMP/fix/fake-home/Library/Application Support/Ollama"
MODELS_COUNT="3"
NODE_FORMULAE="node icu4c@9"
EOF
# shellcheck disable=SC1090,SC1091
source "$TMP/manifest.env"
assert_eq "$OLLAMA_APP_SUPPORT_PATH" "$TMP/fix/fake-home/Library/Application Support/Ollama" "manifest: spaces preserved"
assert_eq "$MODELS_COUNT" "3" "manifest: numeric value"
assert_eq "$NODE_FORMULAE" "node icu4c@9" "manifest: space list"

# --- obd_7zz_banner (uses real 7zz when present; skip otherwise) ---
if obd_find_7zz; then
  b="$(obd_7zz_banner "$OBD_7ZZ")" && assert_contains "$b" "7-Zip" "7zz_banner: contains 7-Zip"
else
  printf '  SKIP 7zz banner (no 7zz available)\n'
fi

rm -rf "$TMP"
finish
