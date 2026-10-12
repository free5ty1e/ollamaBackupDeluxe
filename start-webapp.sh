#!/usr/bin/env bash
# start-webapp.sh — launch the Ollama Backup Deluxe web app.
# Works on a FRESH Mac with no Node installed: if a release bundle's runtime/
# directory is present (official Node tarballs), it extracts the right one to
# .runtime/ and uses it. No internet needed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PORT="${OBD_PORT:-8686}"

# --- locate a node -----------------------------------------------------------
NODE_BIN=""
if [[ "${OBD_NODE_BIN:-}" != "" && -x "$OBD_NODE_BIN" ]]; then
  NODE_BIN="$OBD_NODE_BIN"
elif command -v node >/dev/null 2>&1; then
  NODE_BIN="$(command -v node)"
elif [[ -d "$ROOT/runtime" ]]; then
  ARCH="$(uname -m)"; [[ "$ARCH" == "arm64" ]] || ARCH="x64"
  TB="$(ls "$ROOT"/runtime/node-v*-darwin-${ARCH}.tar.* 2>/dev/null | head -1 || true)"
  [[ -n "$TB" ]] || { echo "No Node found and no runtime/ bundle present." >&2; exit 1; }
  RUNTIME_DIR="$ROOT/.runtime"
  if [[ ! -x "$RUNTIME_DIR/node-current/bin/node" ]]; then
    echo "Extracting bundled Node runtime ($(basename "$TB"))…"
    rm -rf "$RUNTIME_DIR"; mkdir -p "$RUNTIME_DIR"
    tar -xf "$TB" -C "$RUNTIME_DIR"
    mv "$RUNTIME_DIR"/node-v*-darwin-* "$RUNTIME_DIR/node-current"
    xattr -dr com.apple.quarantine "$RUNTIME_DIR" 2>/dev/null || true
  fi
  NODE_BIN="$RUNTIME_DIR/node-current/bin/node"
else
  echo "Node.js is required (system Node or bundled runtime/)." >&2
  echo "On the source Mac: brew install node. In a release bundle: runtime/ should exist." >&2
  exit 1
fi
echo "Using node: $NODE_BIN ($("$NODE_BIN" --version))"

# --- browser -----------------------------------------------------------------
( sleep 1.2; open "http://127.0.0.1:${PORT}" 2>/dev/null || true ) &

exec "$NODE_BIN" "$ROOT/webapp/server.js"
