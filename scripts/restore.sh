#!/usr/bin/env bash
# restore.sh — restore a fully offline backup kit (.7z) created by backup.sh.
# Works with zero internet: uses the 7zz bundled in the release/kit.
#
# Usage:
#   restore.sh --archive <file.7z> [--7zz <path>] [--dest-prefix <dir>]
#              [--purge-existing] [--no-start] [--yes]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # resolved at runtime next to this script
source "$HERE/common.sh"
cd "$HERE/.." || exit 1
require_macos

ARCHIVE="" GIVEN_7ZZ="" PURGE=0 NO_START=0 ASSUME_YES=0 NO_QUIT=0
[[ "${OBD_NO_QUIT:-0}" == "1" ]] && NO_QUIT=1   # test/sandbox guard
while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)        ARCHIVE="$2"; shift 2 ;;
    --7zz)            GIVEN_7ZZ="$2"; shift 2 ;;
    --dest-prefix)    export OBD_DEST_PREFIX="$2"; shift 2 ;;
    --purge-existing) PURGE=1; shift ;;
    --no-start)       NO_START=1; shift ;;
    --no-quit)        NO_QUIT=1; shift ;;
    --yes|-y)         ASSUME_YES=1; shift ;;
    -h|--help)        grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) obd_die "Unknown argument: $1 (see --help)" ;;
  esac
done

obd_check_path_arg "$ARCHIVE" "--archive"
[[ -f "$ARCHIVE" ]] || obd_die "Archive not found: $ARCHIVE"
ARCHIVE="$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")"

# 7zz resolution: --7zz → env/kit → arch-specific release bin → project bin → PATH
[[ -n "$GIVEN_7ZZ" ]] && export OBD_KIT_7ZZ="$GIVEN_7ZZ"
[[ -x "$OBD_BIN_DIR/7zz-$(uname -m)" ]] && export OBD_KIT_7ZZ="${OBD_KIT_7ZZ:-$OBD_BIN_DIR/7zz-$(uname -m)}"
obd_require_7zz

WORK="$(mktemp -d "${TMPDIR:-/tmp}/obd-restore.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Extract + read manifest
# ---------------------------------------------------------------------------
obd_step "Extracting archive inventory…"
"$OBD_7ZZ" x -y -bso0 -bse0 -o"$WORK" "$ARCHIVE" || obd_die "Extraction failed (corrupt archive?)"
[[ -f "$WORK/manifest.env" ]] || obd_die "Archive has no manifest.env — not an OBD backup kit."
xattr -dr com.apple.quarantine "$WORK" 2>/dev/null || true
chmod +x "$WORK/restore-kit/7zz" 2>/dev/null || true

# shellcheck disable=SC1091
source "$WORK/manifest.env"
for k in OBD_VERSION OLLAMA_HOME_PATH ARCH; do
  [[ -n "${!k:-}" ]] || obd_die "Manifest missing key: $k"
done

MANIFEST_ARCH="${ARCH:-}"; MANIFEST_HOST="${HOSTNAME:-}"
OBD_SANDBOX=0; [[ -n "${OBD_DEST_PREFIX:-}" ]] && OBD_SANDBOX=1
if [[ "$OBD_SANDBOX" == "0" && "$NO_QUIT" == "0" ]]; then
  obd_quit_ollama
fi
if [[ "$MANIFEST_ARCH" != "$(uname -m)" ]]; then
  obd_warn "Archive was built on '$MANIFEST_ARCH'; this machine is '$(uname -m)'. Binaries may not run!"
fi

obd_info "Kit from: $MANIFEST_HOST  (${CREATED_UTC:-?})  OBD v${OBD_VERSION:-?}"
obd_info "Ollama ${OLLAMA_VERSION:-?} | Pi ${PI_VERSION:-?} | Node ${NODE_VERSION:-none} | models: ${MODELS_COUNT:-?}"

if [[ "$ASSUME_YES" != "1" ]]; then
  printf 'Restore will replace the components listed above on this machine. Continue? [y/N] '
  read -r reply; [[ "$reply" == "y" || "$reply" == "Y" ]] || obd_die "Aborted by user"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
TS="$(date '+%Y%m%d-%H%M%S')"
set_aside() { # set_aside <existing-path> — rename aside (or purge)
  local p="$1"
  [[ -e "$p" || -L "$p" ]] || return 0
  if [[ "$PURGE" == "1" ]]; then
    obd_elevate rm -rf "$p" || obd_die "Could not remove existing $p"
  else
    local aside="${p}.pre-restore-$TS"
    obd_step "Moving existing $(basename "$p") aside → $(basename "$aside")"
    obd_elevate mv "$p" "$aside" || obd_die "Could not move $p aside (try --purge-existing, or move it manually)"
  fi
}
copy_dir() { # copy_dir <src> <dst>
  mkdir -p "$(dirname "$2")"
  ditto "$1" "$2" || obd_die "Failed copying $1 → $2"
}

# ---------------------------------------------------------------------------
# 1) Ollama application
# ---------------------------------------------------------------------------
if [[ -d "$WORK/Applications/Ollama.app" ]]; then
  APP_DEST="$(obd_dest "${OLLAMA_APP_PATH:-/Applications/Ollama.app}")"
  obd_step "Restoring Ollama app → $APP_DEST"
  if [[ -e "$APP_DEST" ]]; then
    set_aside "$APP_DEST" || {
      obd_err "Could not move the existing Ollama.app aside."
      obd_err "macOS App Management protection may be active:"
      obd_err "  drag /Applications/Ollama.app to Trash manually, then re-run restore."
      exit 3
    }
  fi
  copy_dir "$WORK/Applications/Ollama.app" "$APP_DEST"
fi

# ---------------------------------------------------------------------------
# 2) Ollama data home (~/.ollama)
# ---------------------------------------------------------------------------
if [[ -d "$WORK/home/.ollama" ]]; then
  OHOME_DEST="$(obd_dest "${OLLAMA_HOME_PATH:-$HOME/.ollama}")"
  obd_step "Restoring Ollama data → $OHOME_DEST"
  set_aside "$OHOME_DEST"
  copy_dir "$WORK/home/.ollama" "$OHOME_DEST"
fi

# ---------------------------------------------------------------------------
# 3) Pi (~/.pi + launcher symlink)
# ---------------------------------------------------------------------------
if [[ -d "$WORK/home/.pi" ]]; then
  PI_DEST="$(obd_dest "${PI_HOME_PATH:-$HOME/.pi}")"
  obd_step "Restoring Pi → $PI_DEST"
  set_aside "$PI_DEST"
  copy_dir "$WORK/home/.pi" "$PI_DEST"
fi
if [[ -d "$WORK/home/.pi" && -n "${PI_LAUNCHER_PATH:-}" ]]; then
  PL_DEST="$(obd_dest "$PI_LAUNCHER_PATH")"
  mkdir -p "$(dirname "$PL_DEST")"
  ln -sfn ../../.pi/agent/bin/pi "$PL_DEST"
  obd_ok "Pi launcher symlink → $PL_DEST"
fi

# ---------------------------------------------------------------------------
# 4) Ollama app-support data (~/Library/Application Support/Ollama)
# ---------------------------------------------------------------------------
if [[ -d "$WORK/app-support/Ollama" && -n "${OLLAMA_APP_SUPPORT_PATH:-}" ]]; then
  AS_DEST="$(obd_dest "$OLLAMA_APP_SUPPORT_PATH")"
  obd_step "Restoring Ollama app data → $AS_DEST"
  set_aside "$AS_DEST"
  copy_dir "$WORK/app-support/Ollama" "$AS_DEST"
fi

# ---------------------------------------------------------------------------
# 5) Node runtime (brew Cellar chain + opt/bin symlinks; tarball fallback)
# ---------------------------------------------------------------------------
if [[ -d "$WORK/brew/Cellar" && -n "${BREW_PREFIX:-}" && "$(ls -A "$WORK/brew/Cellar" 2>/dev/null)" ]]; then
  CELLAR_DEST="$(obd_dest "$BREW_PREFIX/Cellar")"
  OPT_DEST="$(obd_dest "$BREW_PREFIX/opt")"
  BIN_DEST="$(obd_dest "$BREW_PREFIX/bin")"
  mkdir -p "$CELLAR_DEST" "$OPT_DEST" "$BIN_DEST"
  obd_step "Restoring Node runtime (brew formulae) → $CELLAR_DEST"
  for fdir in "$WORK/brew/Cellar"/*; do
    f="$(basename "$fdir")"
    set_aside "$CELLAR_DEST/$f"
    copy_dir "$fdir" "$CELLAR_DEST/$f"
  done
  # opt/<formula> relative symlinks recorded in the manifest
  for f in ${NODE_FORMULAE:-}; do
    var="OPT_$(sanitized_key "$f")"; val="${!var:-}"
    if [[ -n "$val" ]]; then
      ln -sfn "$val" "$OPT_DEST/$f"
    fi
  done
  # bin symlinks (node, npm, npx, corepack, …)
  if [[ -f "$WORK/brew/bin-entries.txt" ]]; then
    while IFS=$'\t' read -r name target; do
      [[ -n "$name" && -n "$target" ]] && ln -sfn "$target" "$BIN_DEST/$name"
    done < "$WORK/brew/bin-entries.txt"
  fi
  obd_ok "Node runtime restored (brew chain)"
elif compgen -G "$WORK/node-dist/*.tar.xz" >/dev/null; then
  TARBALL="$(find "$WORK/node-dist" -name "*.tar.xz" | head -1)"
  NODEVER="$(basename "$TARBALL" | sed -E 's/node-v([0-9.]+)-.*/\1/')"
  LIB_DEST="$(obd_dest /usr/local/lib)"; BIN_LOCAL="$(obd_dest /usr/local/bin)"
  obd_step "Node brew chain not in kit — installing fallback runtime from $TARBALL"
  mkdir -p "$LIB_DEST" "$BIN_LOCAL"
  xt="$(mktemp -d)"; tar -xJf "$TARBALL" -C "$xt"
  set_aside "$LIB_DEST/obd-node-v$NODEVER"
  mv "$xt/node-v${NODEVER}-darwin-"* "$LIB_DEST/obd-node-v$NODEVER"
  rm -rf "$xt"
  set_aside "$BIN_LOCAL/node"
  obd_elevate ln -sfn "$LIB_DEST/obd-node-v$NODEVER/bin/node" "$BIN_LOCAL/node" \
    || obd_warn "Could not create /usr/local/bin/node symlink — add it to PATH manually"
  obd_warn "Node restored as fallback runtime at $LIB_DEST/obd-node-v$NODEVER (not brew-managed)"
else
  obd_warn "No Node runtime in this kit — Pi will not run until Node is available."
fi

# ---------------------------------------------------------------------------
# 6) Ollama CLI symlink (/usr/local/bin/ollama)
# ---------------------------------------------------------------------------
if [[ -d "$WORK/Applications/Ollama.app" ]]; then
  APP_DEST="$(obd_dest "${OLLAMA_APP_PATH:-/Applications/Ollama.app}")"
  CLI_DEST="$(obd_dest "${OLLAMA_CLI_PATH:-/usr/local/bin/ollama}")"
  obd_step "Recreating Ollama CLI symlink → $CLI_DEST"
  mkdir -p "$(dirname "$CLI_DEST")"
  [[ -e "$CLI_DEST" || -L "$CLI_DEST" ]] && rm -f "$CLI_DEST" 2>/dev/null || true
  obd_elevate ln -sfn "$APP_DEST/Contents/Resources/ollama" "$CLI_DEST" \
    || obd_warn "Failed to create $CLI_DEST (permissions) — create it manually"
fi

# ---------------------------------------------------------------------------
# 7) Start Ollama + health check (skipped in sandbox mode)
# ---------------------------------------------------------------------------
if [[ "$OBD_SANDBOX" == "0" && "$NO_START" == "0" ]]; then
  obd_step "Starting Ollama…"
  open -a "$(basename "${OLLAMA_APP_PATH:-/Applications/Ollama.app}" .app)" 2>/dev/null || open "${OLLAMA_APP_PATH:-/Applications/Ollama.app}" || true
  ok=""
  for _ in $(seq 1 60); do
    if curl -fsS --max-time 2 http://127.0.0.1:11434/api/version >/dev/null 2>&1; then ok=1; break; fi
    sleep 1
  done
  if [[ -n "$ok" ]]; then obd_ok "Ollama API is up (127.0.0.1:11434)"
  else obd_warn "Ollama API did not respond within 60s — check the Ollama app"; fi
fi

# ---------------------------------------------------------------------------
# 8) Verification (mapped paths so sandbox restores verify correctly)
# ---------------------------------------------------------------------------
obd_step "Verifying restored installation…"
OBD_OLLAMA_APP="$(obd_dest "${OLLAMA_APP_PATH:-/Applications/Ollama.app}")" \
OBD_OLLAMA_HOME="$(obd_dest "${OLLAMA_HOME_PATH:-$HOME/.ollama}")" \
OBD_OLLAMA_APP_SUPPORT="$(obd_dest "${OLLAMA_APP_SUPPORT_PATH:-}")" \
OBD_PI_HOME="$(obd_dest "${PI_HOME_PATH:-$HOME/.pi}")" \
OBD_PI_LAUNCHER="$(obd_dest "${PI_LAUNCHER_PATH:-$HOME/.local/bin/pi}")" \
OBD_BREW_PREFIX="$(obd_dest "${BREW_PREFIX:-/opt/homebrew}")" \
  "$WORK/restore-kit/verify.sh" --manifest "$WORK/manifest.env" --skip-cli-symlink --allow-offline \
  || { obd_err "Verification FAILED — see report above"; exit 4; }

obd_ok "Restore complete. If Ollama autostart was enabled before, re-enable it in Ollama settings."
