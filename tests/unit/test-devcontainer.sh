#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015  # literal $ in fake binaries is intentional; _pass/_fail guarded
# test-devcontainer.sh — the secondary devcontainer restore path.
# Builds a kit with FAKE cached linux payloads (no downloads), then runs
# restore-devcontainer.sh into an OBD_DEST_PREFIX sandbox on macOS.
SUITE_NAME="test-devcontainer"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$HERE/tests/lib/assert.sh"
source "$HERE/scripts/common.sh"
source "$HERE/tests/lib/sandbox.sh"

obd_find_7zz || { echo "  SKIP (no 7zz available)"; exit 0; }
TMP="$HERE/tests/.tmp/test-devcontainer.$$"
trap 'rm -rf "$TMP"' EXIT
make_fixture_tree "$TMP/fix"
FIX="$(cd "$TMP/fix" && pwd -P)"
sandbox_env "$FIX"
export OBD_NO_QUIT=1
export OBD_CACHE_DIR="$TMP/cache"          # isolated cache for fake payloads
mkdir -p "$OBD_CACHE_DIR/devcontainer"
Z="$OBD_7ZZ"

# --- fake linux payloads (scripts that would run on Linux; exec-checked only there) ---
for arch in amd64 arm64; do
  printf '#!/bin/sh\nif [ "${1:-}" = "--version" ]; then echo "ollama version is 0.40.3"; fi\nexit 0\n' > "$OBD_CACHE_DIR/devcontainer/ollama-linux-$arch"
done
for arch in x64 arm64; do
  nd="$TMP/nodedir/node-v9.9.9-linux-$arch"; mkdir -p "$nd/bin"
  printf '#!/bin/sh\nif [ "${1:-}" = "--version" ]; then echo "v9.9.9"; fi\nexit 0\n' > "$nd/bin/node"
  printf '#!/bin/sh\nexit 0\n' > "$nd/bin/npm"
  chmod +x "$nd/bin/node" "$nd/bin/npm"
  tar -cJf "$OBD_CACHE_DIR/devcontainer/node-v9.9.9-linux-$arch.tar.xz" -C "$TMP/nodedir" "node-v9.9.9-linux-$arch"
  printf '#!/bin/sh\nif [ "${1:-}" = "--version" ]; then echo "2.1.251 (Claude Code)"; fi\nexit 0\n' > "$OBD_CACHE_DIR/devcontainer/claude-linux-$arch"
  printf '#!/bin/sh\nif [ "${1:-}" = "--version" ]; then echo "1.19.0"; fi\nexit 0\n' > "$OBD_CACHE_DIR/devcontainer/opencode-linux-$arch"
  printf '#!/bin/sh\nexit 0\n' > "$OBD_CACHE_DIR/devcontainer/7zz-linux-$arch"
done
chmod +x "$OBD_CACHE_DIR/devcontainer/"*
printf '%s\n' "ollama-linux-amd64 ollama-linux-arm64 node claude opencode 7zz" > "$OBD_CACHE_DIR/devcontainer/components.txt"

# --- build the kit (OBD_SKIP_DC=1 skips capture; assembly uses the fake cache) ---
bash "$HERE/scripts/backup.sh" --dest "$TMP" --name dckit --yes >/dev/null 2>&1 \
  || { echo "backup failed"; exit 1; }
assert_file_exists "$TMP/dckit.7z" "main kit built"
assert_file_exists "$TMP/dckit-devcontainer.tar.gz" "devcontainer tarball built"

# --- manifest keys ---
menv="$("$Z" e -y -bso0 -ba -so "$TMP/dckit.7z" manifest.env)"
assert_contains "$menv" 'DEVCONTAINER_KIT="1"'          "manifest: devcontainer kit flag"
assert_contains "$menv" 'DEVCONTAINER_FILE="dckit-devcontainer.tar.gz"' "manifest: dc filename"

# --- tarball structure ---
mkdir -p "$TMP/dc"
tar -xzf "$TMP/dckit-devcontainer.tar.gz" -C "$TMP/dc"
assert_dir_exists "$TMP/dc/obd-devcontainer" "tarball extracts to obd-devcontainer/"
assert_file_exists "$TMP/dc/obd-devcontainer/restore-devcontainer.sh" "restore script in kit"
assert_file_exists "$TMP/dc/obd-devcontainer/common.sh" "common.sh in kit"
assert_file_exists "$TMP/dc/obd-devcontainer/README-DEVCONTAINER.md" "readme in kit"
assert_file_exists "$TMP/dc/obd-devcontainer/ollama-linux-arm64" "ollama arm64 payload"
assert_file_exists "$TMP/dc/obd-devcontainer/node-v9.9.9-linux-arm64.tar.xz" "node arm64 payload"
assert_file_exists "$TMP/dc/obd-devcontainer/claude-linux-x64" "claude x64 payload"
assert_file_exists "$TMP/dc/obd-devcontainer/opencode-linux-arm64" "opencode arm64 payload"
assert_file_exists "$TMP/dc/obd-devcontainer/7zz-linux-arm64" "7zz linux payload"

# --- run the devcontainer restore into a prefix sandbox (on macOS) ---
export OBD_DEST_PREFIX="$TMP/dest"
rc=0
bash "$TMP/dc/obd-devcontainer/restore-devcontainer.sh" \
  --archive "$TMP/dckit.7z" --7zz "$Z" --ollama-host "http://dc-host.test:11434" --yes \
  >"$TMP/restore.log" 2>&1 || rc=$?
assert_exit "$rc" "0" "restore-devcontainer.sh exits 0"
assert_contains "$(cat "$TMP/restore.log")" "Devcontainer restore complete" "restore reports completion"

D="$TMP/dest"
assert_file_exists "$D/usr/local/bin/ollama" "ollama placed in /usr/local/bin (mapped)"
assert_file_exists "$D/usr/local/bin/claude" "claude placed"
assert_file_exists "$D/usr/local/bin/opencode" "opencode placed"
assert_file_exists "$D/usr/local/lib/obd-node-v9.9.9/bin/node" "node dist extracted"
assert_symlink_target "$D/usr/local/bin/node" "$D/usr/local/lib/obd-node-v9.9.9/bin/node" "node symlink"
assert_dir_exists "$D$FIX/fake-home/.pi/agent/install/releases/1.2.3" "pi tree installed from kit"
assert_symlink_target "$D$FIX/fake-home/.local/bin/pi" "../../.pi/agent/bin/pi" "pi launcher symlink"
assert_file_exists "$D$FIX/fake-home/.claude/settings.json" "claude data installed"
assert_file_exists "$D$FIX/fake-home/.config/opencode/opencode.jsonc" "opencode config installed"
assert_file_exists "$D$FIX/fake-home/.local/share/opencode/opencode.db" "opencode session db installed"
assert_file_exists "$D$FIX/fake-home/.local/state/opencode/prompt-history.jsonl" "opencode state installed"
assert_file_exists "$D$FIX/fake-home/.obd-devcontainer.sh" "env file written"
envfile="$(cat "$D$FIX/fake-home/.obd-devcontainer.sh")"
assert_contains "$envfile" 'OLLAMA_HOST="http://dc-host.test:11434"' "OLLAMA_HOST honored"
assert_contains "$envfile" '.local/bin' "PATH wiring present"
assert_contains "$(cat "$D$FIX/fake-home/.bashrc")" ".obd-devcontainer.sh" "bashrc sources env file"

# --- --no-devcontainer suppresses the tarball ---
bash "$HERE/scripts/backup.sh" --dest "$TMP" --name nodc --no-devcontainer --yes >/dev/null 2>&1
assert_file_exists "$TMP/nodc.7z" "no-dc backup built"
[[ ! -f "$TMP/nodc-devcontainer.tar.gz" ]] && _pass "--no-devcontainer: no tarball" || _fail "--no-devcontainer: no tarball"
m2="$("$Z" e -y -bso0 -ba -so "$TMP/nodc.7z" manifest.env)"
assert_contains "$m2" 'DEVCONTAINER_KIT="0"' "manifest: dc flag off"

finish
