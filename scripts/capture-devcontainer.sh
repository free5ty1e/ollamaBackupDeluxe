#!/usr/bin/env bash
# shellcheck disable=SC2015,SC1091  # ok/skip are side-effect-only; common.sh resolved at runtime
# capture-devcontainer.sh — capture Linux payloads for the devcontainer kit.
# Runs on the macOS HOST at backup time (internet required HERE, never at restore).
# Everything is cached under cache/devcontainer/ — first backup pays the download,
# later ones reuse it. Every step is best-effort: failures skip that payload and are
# reported; the backup itself never fails because of this script.
#
# Payloads captured (glibc builds — Debian/Ubuntu-style devcontainers):
#   ollama-linux-<amd64|arm64>       CLI binary (extracted from the official tarball;
#                                    talks to the host's server over the network)
#   node-linux-<x64|arm64>.tar.xz    official Node dist (runs the Pi harness)
#   claude-linux-<arm64|x64>         Claude Code native Linux build (checksum-verified)
#   opencode-linux-<arm64|x64>       OpenCode Linux build
#   7zz-linux-<arm64|x64>            7-Zip for Linux (self-extraction in the container)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/common.sh"
cd "$HERE/.." || exit 1

CACHE="$OBD_CACHE_DIR/devcontainer"
mkdir -p "$CACHE"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/obd-dc.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
DC_COMPONENTS=""

ok()   { DC_COMPONENTS="$DC_COMPONENTS $1"; obd_ok "$1 payload captured"; }
skip() { obd_warn "devcontainer payload '$1' SKIPPED: $2"; }

fetch() { # fetch <url> <out> — curl with retries
  curl -fL --retry 3 --max-time 3600 -o "$out_tmp" "$url" 2>/dev/null
}
out_tmp=""; url=""

# --- 1) ollama Linux CLI (version-pinned to the installed ollama) -------------
ollama_ver="$(obd_detect_ollama_version "$OBD_OLLAMA_APP/Contents/Resources/ollama" 2>/dev/null || true)"
[[ -n "$ollama_ver" ]] || ollama_ver="$(ollama --version 2>/dev/null | awk '/version is/{print $4}')"
if [[ -z "$ollama_ver" ]]; then
  skip "ollama" "no local ollama version detected"
else
  for arch in amd64 arm64; do
    out="$CACHE/ollama-linux-$arch"
    if [[ -x "$out" ]]; then ok "ollama-linux-$arch (cached)"; continue; fi
    vp="?version=$ollama_ver"
    got=""
    for ext in tar.zst tgz; do
      url="https://ollama.com/download/ollama-linux-$arch.$ext$vp"
      out_tmp="$TMP/ollama.$ext"
      if fetch; then
        obd_step "ollama-linux-$arch: downloaded ($(human_size "$(wc -c < "$out_tmp" | tr -d ' ')")), extracting bin/ollama…"
        mkdir -p "$TMP/ox"
        if [[ "$ext" == "tar.zst" ]]; then tar -xf "$out_tmp" -C "$TMP/ox" bin/ollama 2>/dev/null || tar -xzf "$out_tmp" -C "$TMP/ox" bin/ollama 2>/dev/null || true
        else tar -xzf "$out_tmp" -C "$TMP/ox" bin/ollama 2>/dev/null || true; fi
        if [[ -x "$TMP/ox/bin/ollama" ]]; then
          mv "$TMP/ox/bin/ollama" "$out"; chmod +x "$out"; got=1; break
        fi
      fi
    done
    rm -rf "$TMP/ox"
    [[ -n "$got" ]] && ok "ollama-linux-$arch" || skip "ollama-linux-$arch" "download failed (offline?)"
  done
fi

# --- 2) Node Linux dists (runs the Pi harness in the container) ---------------
node_ver="$(node --version 2>/dev/null | sed 's/^v//' || true)"
if [[ -z "$node_ver" ]]; then
  skip "node" "no local node to determine version"
else
  for arch in x64 arm64; do
    out="$CACHE/node-v${node_ver}-linux-$arch.tar.xz"
    if [[ -s "$out" ]]; then ok "node-linux-$arch (cached)"; continue; fi
    url="https://nodejs.org/dist/v${node_ver}/node-v${node_ver}-linux-$arch.tar.xz"
    out_tmp="$out.part"
    if fetch; then mv "$out_tmp" "$out"; ok "node-linux-$arch"
    else rm -f "$out_tmp"; skip "node-linux-$arch" "download failed"; fi
  done
fi

# --- 3) Claude Code Linux builds (checksum-verified via official manifest) ----
claude_ver="$(obd_detect_claude_version 2>/dev/null || true)"
if [[ -z "$claude_ver" ]]; then
  skip "claude" "no local claude version detected"
else
  base="https://downloads.claude.ai/claude-code-releases"
  manifest="$TMP/manifest.json"
  url="$base/$claude_ver/manifest.json"; out_tmp="$manifest"
  if fetch && [[ -s "$manifest" ]]; then
    for arch in arm64 x64; do
      out="$CACHE/claude-linux-$arch"
      [[ -s "$out" ]] && { ok "claude-linux-$arch (cached)"; continue; }
      sum="$(python3 -c "import json,sys;d=json.load(open('$manifest'));p=d['platforms'].get('linux-$arch');print((p or {}).get('checksum',''))" 2>/dev/null || true)"
      if [[ -z "$sum" ]]; then skip "claude-linux-$arch" "not in manifest"; continue; fi
      url="$base/$claude_ver/linux-$arch/claude"; out_tmp="$out.part"
      if fetch && [[ "$(sha256_file "$out.part")" == "$sum" ]]; then
        mv "$out.part" "$out"; chmod +x "$out"; ok "claude-linux-$arch"
      else
        rm -f "$out.part"; skip "claude-linux-$arch" "download/checksum failed"
      fi
    done
  else
    skip "claude" "manifest unavailable at $base/$claude_ver"
  fi
fi

# --- 4) OpenCode Linux builds -------------------------------------------------
oc_ver="$(obd_detect_opencode_version 2>/dev/null || true)"
if [[ -z "$oc_ver" ]]; then
  skip "opencode" "no local opencode version detected"
else
  for arch in arm64 x64; do
    out="$CACHE/opencode-linux-$arch"
    [[ -s "$out" ]] && { ok "opencode-linux-$arch (cached)"; continue; }
    got=""
    for ext in zip tar.gz; do
      url="https://github.com/anomalyco/opencode/releases/download/v${oc_ver}/opencode-linux-$arch.$ext"
      out_tmp="$TMP/oc.$ext"
      fetch || continue
      mkdir -p "$TMP/ocx"
      if [[ "$ext" == "zip" ]]; then unzip -qo "$out_tmp" -d "$TMP/ocx" 2>/dev/null || true
      else tar -xzf "$out_tmp" -C "$TMP/ocx" 2>/dev/null || true; fi
      binf="$(find "$TMP/ocx" -type f -name opencode | head -1)"
      if [[ -n "$binf" ]]; then cp "$binf" "$out"; chmod +x "$out"; got=1; break; fi
    done
    rm -rf "$TMP/ocx"
    [[ -n "$got" ]] && ok "opencode-linux-$arch" || skip "opencode-linux-$arch" "download/extract failed"
  done
fi

# --- 5) 7-Zip for Linux (kit self-extraction inside the container) ------------
tag="$(curl -fsSL --max-time 30 https://api.github.com/repos/ip7z/7zip/releases/latest 2>/dev/null |
        { grep -m1 '"tag_name"' || true; } | sed -E 's/.*"v?([^"]+)".*/\1/')"
if [[ -z "$tag" ]]; then
  skip "7zz" "cannot determine latest 7-Zip release"
else
  vnum="${tag//./}"
  for arch in arm64 x64; do
    out="$CACHE/7zz-linux-$arch"
    [[ -s "$out" ]] && { ok "7zz-linux-$arch (cached)"; continue; }
    url="https://github.com/ip7z/7zip/releases/download/$tag/7z${vnum}-linux-$arch.tar.xz"
    out_tmp="$TMP/7z.tar.xz"
    if fetch; then
      mkdir -p "$TMP/7zx"
      tar -xJf "$out_tmp" -C "$TMP/7zx" 7zz 2>/dev/null || true
      [[ -x "$TMP/7zx/7zz" ]] && { cp "$TMP/7zx/7zz" "$out"; chmod +x "$out"; ok "7zz-linux-$arch"; } || skip "7zz-linux-$arch" "extract failed"
      rm -rf "$TMP/7zx"
    else skip "7zz-linux-$arch" "download failed"; fi
  done
fi

DC_COMPONENTS="${DC_COMPONENTS# }"
printf '%s\n' "$DC_COMPONENTS" > "$CACHE/components.txt"
obd_step "Devcontainer payload: ${DC_COMPONENTS:-(nothing captured)}"
