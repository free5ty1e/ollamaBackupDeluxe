#!/usr/bin/env bash
# prerequisites.sh — one-time setup for Ollama Backup Deluxe.
# Ensures a 7-Zip (7zz) binary is available in ./bin (embedded into every backup
# so restores work offline), optionally prefetches the official Node.js dist
# tarball (fallback runtime), and audits the inference stack.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # resolved at runtime next to this script
source "$HERE/common.sh"
cd "$HERE/.." || exit 1
require_macos

SKIP_NODE_DIST=0
for arg in "$@"; do
  case "$arg" in
    -h|--help)         sed -n '2,10p' "$0"; exit 0 ;;
    --skip-node-dist)  SKIP_NODE_DIST=1 ;;
    *) obd_warn "unknown arg: $arg" ;;
  esac
done

mkdir -p "$OBD_BIN_DIR" "$OBD_CACHE_DIR/node-dist" "$OBD_LOG_DIR"
ARCH="$(uname -m)"; [[ "$ARCH" == "arm64" ]] && MAC_ARCH="arm64" || MAC_ARCH="x64"

# ---------------------------------------------------------------------------
# 1) 7-Zip (7zz)
# ---------------------------------------------------------------------------
have_7zz() {
  [[ -x "$1" ]] || return 1
  obd_7zz_banner "$1" >/dev/null
}

if have_7zz "$OBD_BIN_DIR/7zz"; then
  obd_ok "7-Zip already present: $OBD_BIN_DIR/7zz"
else
  obd_step "Acquiring 7-Zip (7zz) for macOS ${MAC_ARCH}…"
  got=""
  # a) system-installed?
  for c in 7zz 7zzs; do
    if p="$(command -v "$c" 2>/dev/null)" && have_7zz "$p"; then
      cp "$p" "$OBD_BIN_DIR/7zz" && got=copy; break
    fi
  done
  # b) Homebrew
  if [[ -z "$got" ]] && command -v brew >/dev/null 2>&1; then
    if { brew list --formula 2>/dev/null || true; } | grep -x 'sevenzip' >/dev/null || brew install sevenzip; then
      if p="$(command -v 7zz 2>/dev/null)" && have_7zz "$p"; then
        cp "$p" "$OBD_BIN_DIR/7zz" && got=brew
      fi
    fi
  fi
  # c) direct download from the official 7-Zip project (works without brew)
  if [[ -z "$got" ]]; then
    api_json="$(curl -fsSL --max-time 30 https://api.github.com/repos/ip7z/7zip/releases/latest || true)"
    tag="$(printf '%s' "$api_json" | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/' || true)"
    [[ -n "$tag" ]] || obd_die "Could not determine latest 7-Zip release (offline?)."
    vnum="${tag//./}"
    # macOS assets have been arch-agnostic (…-mac.tar.xz); try arch-specific first
    url="https://github.com/ip7z/7zip/releases/download/$tag/7z${vnum}-mac-${MAC_ARCH}.tar.xz"
    if ! curl -fsIL --max-time 20 "$url" >/dev/null 2>&1; then
      url="https://github.com/ip7z/7zip/releases/download/$tag/7z${vnum}-mac.tar.xz"
    fi
    obd_step "Downloading $url"
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    curl -fL --retry 3 -o "$tmp/7z.tar.xz" "$url" || obd_die "Download failed."
    tar -xJf "$tmp/7z.tar.xz" -C "$tmp" || obd_die "Extraction of 7zz failed."
    [[ -x "$tmp/7zz" ]] || obd_die "Archive did not contain a 7zz binary."
    mv "$tmp/7zz" "$OBD_BIN_DIR/7zz"
    got=download
  fi
  chmod +x "$OBD_BIN_DIR/7zz"
  xattr -dr com.apple.quarantine "$OBD_BIN_DIR/7zz" 2>/dev/null || true
  have_7zz "$OBD_BIN_DIR/7zz" || obd_die "7zz still not working after install."
  obd_ok "7-Zip installed via $got → $OBD_BIN_DIR/7zz"
fi

# ---------------------------------------------------------------------------
# 2) Node.js fallback dist tarball (optional but recommended)
# ---------------------------------------------------------------------------
obd_detect_node
if [[ "$SKIP_NODE_DIST" == "1" ]]; then
  obd_step "Skipping node-dist prefetch (--skip-node-dist)"
elif [[ -z "$OBD_NODE_VERSION" ]]; then
  obd_warn "Node not found — cannot prefetch dist tarball. Pi needs Node; install Node first."
else
  ver="${OBD_NODE_VERSION#v}"
  fname="node-v${ver}-darwin-${MAC_ARCH}.tar.xz"
  dest="$OBD_CACHE_DIR/node-dist/$fname"
  if [[ -s "$dest" ]]; then
    obd_ok "Node dist tarball already cached: $dest"
  else
    url="https://nodejs.org/dist/v${ver}/${fname}"
    obd_step "Prefetching fallback Node runtime: $url"
    if curl -fL --retry 3 -o "$dest.part" "$url"; then
      mv "$dest.part" "$dest"
      obd_ok "Cached $fname ($(human_size "$(wc -c < "$dest" | tr -d ' ')"))"
    else
      rm -f "$dest.part"; obd_warn "Node tarball download failed (backup will still work; only the runtime fallback is skipped)"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 3) Component audit
# ---------------------------------------------------------------------------
echo
obd_step "System audit"
printf '  %-28s %s\n' "macOS:" "$(sw_vers -productVersion) ($(uname -m))"
printf '  %-28s %s\n' "7-Zip:" "$(obd_7zz_banner "$OBD_BIN_DIR/7zz")"
if [[ -d "$OBD_OLLAMA_APP" ]]; then
  v="$(obd_detect_ollama_version "$OBD_OLLAMA_APP/Contents/MacOS/../Resources/ollama" 2>/dev/null || true)"
  [[ -n "$v" ]] || v="$( ( "$OBD_OLLAMA_APP/Contents/Resources/ollama" --version 2>/dev/null | head -1 ) || true)"
  printf '  %-28s %s (%s)\n' "Ollama app:" "${v:-present, version n/a}" "$OBD_OLLAMA_APP"
  printf '  %-28s %s\n' "Ollama data:" "$OBD_OLLAMA_HOME ($(human_size $(( $(dir_size_kb "$OBD_OLLAMA_HOME") * 1024 ))))"
  printf '  %-28s %s\n' "Ollama models:" "$(obd_model_list "$OBD_OLLAMA_HOME" | wc -l | tr -d ' ') models"
else
  printf '  %-28s %s\n' "Ollama app:" "NOT FOUND ($OBD_OLLAMA_APP)"
fi
if [[ -d "$OBD_PI_HOME" ]]; then
  pv="$("$OBD_PI_HOME/agent/bin/pi" --version 2>/dev/null | head -1 || true)"
  printf '  %-28s %s (%s)\n' "Pi:" "${pv:-present}" "$OBD_PI_HOME"
else
  printf '  %-28s %s\n' "Pi:" "NOT FOUND ($OBD_PI_HOME)"
fi
if [[ -n "$OBD_NODE_VERSION" ]]; then
  printf '  %-28s %s (%s, %s)\n' "Node:" "$OBD_NODE_VERSION" "$OBD_NODE_MODE" "$OBD_NODE_REAL"
else
  printf '  %-28s %s\n' "Node:" "NOT FOUND"
fi
echo
obd_ok "Prerequisites ready. Start the web app with: $OBD_PROJECT_DIR/start-webapp.sh"
