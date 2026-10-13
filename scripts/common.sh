#!/usr/bin/env bash
# common.sh — shared library for Ollama Backup Deluxe
# shellcheck shell=bash

[[ -n "${OBD_COMMON_LOADED:-}" ]] && return 0
OBD_COMMON_LOADED=1
# shellcheck disable=SC2034  # library API, consumed by sourcing scripts
OBD_VERSION="1.0.0"

# ----------------------------------------------------------------------------
# Logging
# ----------------------------------------------------------------------------
OBD_TTY=""
[[ -t 2 ]] && OBD_TTY=1
obd_color() { # obd_color <code> <text>
  if [[ -n "$OBD_TTY" ]]; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi
}
obd_ts()   { date '+%H:%M:%S'; }
_obd_emit() { # _obd_emit <color> <label> <message...>
  local pfx tag
  pfx="$(obd_color '36' "[obd $(obd_ts)]")"
  tag="$(obd_color "$1" "$2")"
  shift 2
  printf '%s %s %s\n' "$pfx" "$tag" "$*"
}
obd_info() { _obd_emit '90' 'INFO ' "$@"; }
obd_ok()   { _obd_emit '32' 'OK   ' "$@"; }
obd_warn() { _obd_emit '33' 'WARN ' "$@"; }
obd_err()  { _obd_emit '31' 'ERROR' "$@" >&2; }
obd_step() { _obd_emit '95' '>>   ' "$@"; }
obd_die()  { obd_err "$*"; exit 1; }

# ----------------------------------------------------------------------------
# Locations
# ----------------------------------------------------------------------------
OBD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OBD_PROJECT_DIR="${OBD_PROJECT_DIR:-$(cd "$OBD_SCRIPT_DIR/.." && pwd)}"
# shellcheck disable=SC2034  # library API, consumed by sourcing scripts
OBD_BIN_DIR="${OBD_BIN_DIR:-$OBD_PROJECT_DIR/bin}"
# shellcheck disable=SC2034
OBD_CACHE_DIR="${OBD_CACHE_DIR:-$OBD_PROJECT_DIR/cache}"
# shellcheck disable=SC2034
OBD_LOG_DIR="${OBD_LOG_DIR:-$OBD_PROJECT_DIR/logs}"

# ----------------------------------------------------------------------------
# Overridable component paths (the testability contract — see docs/plans/)
# ----------------------------------------------------------------------------
OBD_HOME="${OBD_HOME:-$HOME}"
OBD_OLLAMA_APP="${OBD_OLLAMA_APP:-/Applications/Ollama.app}"
OBD_OLLAMA_CLI="${OBD_OLLAMA_CLI:-/usr/local/bin/ollama}"
OBD_OLLAMA_HOME="${OBD_OLLAMA_HOME:-$OBD_HOME/.ollama}"
OBD_OLLAMA_APP_SUPPORT="${OBD_OLLAMA_APP_SUPPORT:-$OBD_HOME/Library/Application Support/Ollama}"
OBD_PI_HOME="${OBD_PI_HOME:-$OBD_HOME/.pi}"
OBD_PI_LAUNCHER="${OBD_PI_LAUNCHER:-$OBD_HOME/.local/bin/pi}"
OBD_CLAUDE_HOME="${OBD_CLAUDE_HOME:-$OBD_HOME/.claude}"
OBD_CLAUDE_SHARE="${OBD_CLAUDE_SHARE:-$OBD_HOME/.local/share/claude}"
OBD_CLAUDE_LAUNCHER="${OBD_CLAUDE_LAUNCHER:-$OBD_HOME/.local/bin/claude}"
OBD_OPENCODE_HOME="${OBD_OPENCODE_HOME:-$OBD_HOME/.opencode}"
OBD_OPENCODE_CONFIG="${OBD_OPENCODE_CONFIG:-$OBD_HOME/.config/opencode}"
OBD_OPENCODE_SHARE="${OBD_OPENCODE_SHARE:-$OBD_HOME/.local/share/opencode}"
OBD_OPENCODE_STATE="${OBD_OPENCODE_STATE:-$OBD_HOME/.local/state/opencode}"
# Shell rc files captured for PATH wiring (launchers are useless if PATH lacks their dirs)
OBD_SHELL_RCS="${OBD_SHELL_RCS:-.zshrc .zprofile .zshenv .bashrc .bash_profile}"
# Devcontainer secondary restore: where the container finds the host's ollama
OBD_DC_OLLAMA_HOST="${OBD_DC_OLLAMA_HOST:-http://host.docker.internal:11434}"
case "$(uname -m)" in
  arm64)  OBD_BREW_PREFIX="${OBD_BREW_PREFIX:-/opt/homebrew}" ;;
  *)      OBD_BREW_PREFIX="${OBD_BREW_PREFIX:-/usr/local}" ;;
esac

# ----------------------------------------------------------------------------
# Small helpers
# ----------------------------------------------------------------------------
require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || obd_die "This tool only supports macOS."
}

human_size() { # bytes -> human
  local b=${1:-0} u=(B KB MB GB TB) i=0
  while (( b >= 1024 && i < 4 )); do b=$(( b / 1024 )); ((i++)); done
  printf '%d%s' "$b" "${u[$i]}"
}
dir_size_kb() { # du -sk with graceful fallback
  local p="$1"; [[ -e "$p" ]] || { echo 0; return; }
  du -sk "$p" 2>/dev/null | awk '{print $1}'
}
sha256_file() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

sanitized_key() { # icu4c@78 -> ICU4C_78  (for manifest KEY= names)
  printf '%s' "$1" | tr 'a-z.@+' 'A-Z____' | tr -c 'A-Z0-9_' '_'
}

# ----------------------------------------------------------------------------
# Component detection
# ----------------------------------------------------------------------------
obd_detect_ollama_version() { # prints version or empty
  local cli="$1"
  if [[ -x "$cli" ]]; then "$cli" --version 2>/dev/null | head -1 | awk '{print $NF}' | tr -d '"'
  elif [[ -d "$(dirname "$cli")" ]]; then :; fi
}

# Enumerate installed models from the manifests tree — no server needed.
# Handles both classic (manifests/registry.ollama.ai/library/x/tag) and
# manifests-v2/ollama.com/... layouts. Prints "name:tag" (or "ns/name:tag").
obd_model_list() { # obd_model_list <ollama_home>
  local models_dir="$1/models" root ns name tag rest
  [[ -d "$models_dir" ]] || return 0
  for root in "$models_dir/manifests" "$models_dir/manifests-v2"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r -d '' mf; do
      rest="${mf#"$root"/}"          # registry.ollama.ai/library/gemma4/e4b
      rest="${rest#*/}"              # strip registry host
      ns="${rest%%/*}"; rest="${rest#*/}"
      name="${rest%%/*}"; tag="${rest#*/}"
      [[ -n "$ns" && -n "$name" && -n "$tag" ]] || continue
      if [[ "$ns" == "library" ]]; then printf '%s:%s\n' "$name" "$tag"
      else printf '%s/%s:%s\n' "$ns" "$name" "$tag"; fi
    done < <(find "$root" -type f -print0 2>/dev/null | sort -z)
  done | sort -u
}

# Harness detection (claude / opencode). Sets OBD_CLAUDE_VERSION,
# OBD_OPENCODE_VERSION (empty when not installed).
obd_detect_claude_version() {
  local l="${OBD_CLAUDE_LAUNCHER:-}"
  [[ -x "$l" ]] || l="$OBD_CLAUDE_SHARE/$(find "$OBD_CLAUDE_SHARE/versions" -maxdepth 1 -mindepth 1 -type f 2>/dev/null | sort -V | tail -1 | xargs basename 2>/dev/null)"
  [[ -x "$l" ]] || return 0
  "$l" --version 2>/dev/null | head -1 | awk '{print $1}'
}
obd_detect_opencode_version() {
  local l="${OBD_OPENCODE_HOME:-}/bin/opencode"
  [[ -x "$l" ]] || return 0
  "$l" --version 2>/dev/null | head -1 | awk '{print $1}'
}

# Node runtime detection. Sets (when found):
#   OBD_NODE_MODE   brew | system | none
#   OBD_NODE_BIN    absolute path to node
#   OBD_NODE_VERSION
#   OBD_NODE_REAL   resolved real path
#   OBD_NODE_FORMULAE  brew formula list backing this node (brew mode only)
obd_detect_node() {
  # shellcheck disable=SC2034  # library API, consumed by sourcing scripts
  OBD_NODE_MODE="none"; OBD_NODE_BIN="${OBD_NODE_BIN:-}"; OBD_NODE_VERSION=""; OBD_NODE_REAL=""
  local cand="${OBD_NODE_BIN:-$(command -v node 2>/dev/null || true)}"
  [[ -n "$cand" && -x "$cand" ]] || return 0
  OBD_NODE_BIN="$cand"
  # shellcheck disable=SC2034
  OBD_NODE_VERSION="$("$cand" --version 2>/dev/null || true)"
  OBD_NODE_REAL="$(readlink -f "$cand" 2>/dev/null || printf '%s' "$cand")"
  case "$OBD_NODE_REAL" in
    "$OBD_BREW_PREFIX"/Cellar/*)
      OBD_NODE_MODE="brew"
      local formula="${OBD_NODE_REAL#"$OBD_BREW_PREFIX"/Cellar/}"; formula="${formula%%/*}"
      # shellcheck disable=SC2034
      OBD_NODE_FORMULAE="$(obd_brew_formula_chain "$formula")"
      ;;
    *) # shellcheck disable=SC2034
       OBD_NODE_MODE="system" ;;
  esac
}

# formula + all its runtime deps that exist in the Cellar
obd_brew_formula_chain() {
  local formula="$1" deps=""
  if command -v brew >/dev/null 2>&1; then
    deps="$(brew deps "$formula" 2>/dev/null || true)"
  fi
  printf '%s %s' "$formula" "$deps" | tr ' ' '\n' | awk 'NF' | sort -u |
    while IFS= read -r f; do
      if [[ -d "$OBD_BREW_PREFIX/Cellar/$f" ]]; then printf '%s\n' "$f"; fi
    done
}

# Ollama running / quit
obd_ollama_running() {
  pgrep -x Ollama >/dev/null 2>&1 || pgrep -f 'ollama serve' >/dev/null 2>&1
}
obd_quit_ollama() {
  obd_ollama_running || return 0
  obd_step "Quitting Ollama…"
  osascript -e 'tell application "Ollama" to quit' >/dev/null 2>&1 || true
  pkill -x Ollama >/dev/null 2>&1 || true
  pkill -f 'ollama serve' >/dev/null 2>&1 || true
  local i=0
  while obd_ollama_running && (( i < 20 )); do sleep 0.5; ((i++)); done
  obd_ollama_running && obd_warn "Ollama still running; continuing anyway"
  return 0
}

# ----------------------------------------------------------------------------
# Elevation: run a command that may need root. Tries directly; on EPERM/EACCES
# falls back to macOS GUI admin prompt (osascript). Usage: obd_elevate cmd args…
# ----------------------------------------------------------------------------
obd_elevate() {
  if "$@" 2>/dev/null; then return 0; fi
  local rc=$?
  obd_step "Direct write failed (rc=$rc) — requesting administrator privileges…"
  local script
  script="do shell script \"$(printf '%q ' "$@")\" with administrator privileges"
  osascript -e "$script" >/dev/null 2>&1
}

# ----------------------------------------------------------------------------
# 7-Zip locator. Sets OBD_7ZZ (path) or fails with actionable message.
# Search order: OBD_7ZZ env → archive-local restore-kit (caller supplies via
# OBD_KIT_7ZZ) → project bin/ → PATH.
# ----------------------------------------------------------------------------
obd_find_7zz() {
  local c
  for c in "${OBD_7ZZ:-}" "${OBD_KIT_7ZZ:-}" "$OBD_BIN_DIR/7zz"; do
    [[ -n "$c" && -x "$c" ]] && { OBD_7ZZ="$c"; return 0; }
  done
  for c in 7zz 7zzs 7z; do
    c="$(command -v "$c" 2>/dev/null || true)"
    [[ -n "$c" && -x "$c" ]] && { OBD_7ZZ="$c"; return 0; }
  done
  return 1
}
obd_require_7zz() {
  obd_find_7zz && return 0
  obd_err "7-Zip (7zz) is required but was not found."
  obd_err "Run: $OBD_SCRIPT_DIR/prerequisites.sh   (needs internet once, or brew install sevenzip)"
  exit 1
}

# Banner-safe 7zz probe: capture ALL output (usage text is tiny), find the
# version line — the first line of 7zz output is blank.
obd_7zz_banner() {
  local out=""; out="$("$1" 2>/dev/null || true)" || true
  local line
  while IFS= read -r line; do
    [[ "$line" == *'7-Zip'* ]] && { printf '%s' "$line"; return 0; }
  done <<< "$out"
  return 1
}

# ----------------------------------------------------------------------------
# Restore destination mapping (sandbox testing): with OBD_DEST_PREFIX set, every
# absolute destination lands INSIDE the prefix (prefix + original absolute path),
# e.g. /Applications/Ollama.app → $PREFIX/Applications/Ollama.app and
# /usr/local/bin/ollama → $PREFIX/usr/local/bin/ollama. Real mode: passthrough.
# ----------------------------------------------------------------------------
obd_dest() { # obd_dest <absolute-path> -> possibly prefixed path
  local p="$1"
  if [[ -n "${OBD_DEST_PREFIX:-}" ]]; then
    printf '%s%s\n' "${OBD_DEST_PREFIX%/}" "$p"
  else
    printf '%s\n' "$p"
  fi
}

# Validate that a user-supplied archive/dest path is sane
# (bash strings cannot contain NUL bytes, so only the emptiness check applies)
obd_check_path_arg() {
  local p="$1" what="$2"
  [[ -n "$p" ]] || obd_die "$what: path is empty"
  return 0
}
