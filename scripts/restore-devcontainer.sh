#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC1091  # A&&B||C patterns are guarded; rc templates intentionally literal; common.sh resolved at runtime
# restore-devcontainer.sh — SECONDARY restore for Linux devcontainers.
# Installs the ollama CLI + harnesses (pi, claude, opencode) and their configs
# so `ollama launch pi` / `ollama launch claude` work inside the container and
# talk to the HOST's Ollama server over the network. NO models are installed —
# they live on the host (OLLAMA_HOST).
#
# Runs fully offline: everything ships in the devcontainer kit tarball.
#   (on the host)   backup produced:  <name>-devcontainer.tar.gz  +  <name>.7z
#   (in container)  tar -xzf <name>-devcontainer.tar.gz
#                   cd obd-devcontainer && ./restore-devcontainer.sh --archive /kit/<name>.7z
#
# Options:
#   --archive <file.7z>    the main backup kit (harness configs + pi tree come from it)
#   --ollama-host <url>    default: http://host.docker.internal:11434
#   --dest-prefix <dir>    sandbox: prefix all destinations (tests)
#   --7zz <path>           override bundled 7zz
#   --yes                  non-interactive
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/common.sh"

ARCHIVE="" OLLAMA_HOST="${OBD_DC_OLLAMA_HOST:-http://host.docker.internal:11434}" ASSUME_YES=0
LINUX_ARCH=""; case "$(uname -m)" in x86_64) LINUX_ARCH="x64" ;; aarch64|arm64) LINUX_ARCH="arm64" ;; esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)     ARCHIVE="$2"; shift 2 ;;
    --ollama-host) OLLAMA_HOST="$2"; shift 2 ;;
    --dest-prefix) export OBD_DEST_PREFIX="$2"; shift 2 ;;
    --7zz)         export OBD_KIT_7ZZ="$2"; shift 2 ;;
    --yes|-y)      ASSUME_YES=1; shift ;;
    -h|--help)     grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) obd_die "Unknown argument: $1 (see --help)" ;;
  esac
done

obd_check_path_arg "$ARCHIVE" "--archive"
[[ -f "$ARCHIVE" ]] || obd_die "Archive not found: $ARCHIVE"
ARCHIVE="$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")"

# bundled linux 7zz (no sudo, no brew, nothing to install)
[[ -x "$HERE/7zz-linux-$LINUX_ARCH" ]] && export OBD_KIT_7ZZ="${OBD_KIT_7ZZ:-$HERE/7zz-linux-$LINUX_ARCH}"
obd_require_7zz

IS_LINUX=0; [[ "$(uname -s)" == "Linux" ]] && IS_LINUX=1
if [[ "$IS_LINUX" == "0" && -z "${OBD_DEST_PREFIX:-}" ]]; then
  obd_warn "Not running on Linux — continuing (binaries will be placed but not executed)"
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/obd-dc-restore.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# --- extract the main kit (harness configs + pi tree live there) --------------
obd_step "Extracting backup kit…"
"$OBD_7ZZ" x -y -bso0 -bse0 -o"$WORK" "$ARCHIVE" || obd_die "Extraction failed (corrupt kit?)"
[[ -f "$WORK/manifest.env" ]] || obd_die "Not an OBD backup kit (no manifest.env)."
# shellcheck disable=SC1091
source "$WORK/manifest.env"
xattr -dr com.apple.quarantine "$HERE" 2>/dev/null || true

if [[ "$ASSUME_YES" != "1" ]]; then
  printf 'Restore devcontainer toolset from %s (OLLAMA_HOST=%s)? [y/N] ' "$(basename "$ARCHIVE")" "$OLLAMA_HOST"
  read -r reply; [[ "$reply" == "y" || "$reply" == "Y" ]] || obd_die "Aborted by user"
fi

# helpers ---------------------------------------------------------------------
set_aside() { local p="$1"; [[ -e "$p" || -L "$p" ]] || return 0
  obd_step "Moving existing $(basename "$p") aside"; mv "$p" "$p.pre-restore-$(date '+%Y%m%d-%H%M%S')"; }
copy_dir() { mkdir -p "$(dirname "$2")"; cp -a "$1" "$2"; }
install_bin() { # install_bin <src> <name> — /usr/local/bin preferred, ~/.local/bin fallback
  local src="$1" name="$2" dest
  if [[ -n "${OBD_DEST_PREFIX:-}" ]]; then
    dest="$(obd_dest /usr/local/bin)/$name"
  elif [[ -w /usr/local/bin ]] || sudo -n true 2>/dev/null; then
    dest="/usr/local/bin/$name"
  else
    dest="$HOME/.local/bin/$name"; mkdir -p "$HOME/.local/bin"
    obd_warn "$name installed to ~/.local/bin (no write access to /usr/local/bin)"
  fi
  mkdir -p "$(dirname "$dest")"
  cp -f "$src" "$dest" && chmod +x "$dest"
  printf '%s' "$dest"
}

# --- ollama CLI ---------------------------------------------------------------
if [[ -x "$HERE/ollama-linux-$LINUX_ARCH" ]]; then
  odest="$(install_bin "$HERE/ollama-linux-$LINUX_ARCH" ollama)"
  obd_ok "ollama CLI → $odest"
else
  odest=""
  obd_warn "ollama Linux binary not in kit — install it manually from the kit README"
fi

# --- node (runs pi) -----------------------------------------------------------
NODE_TARBALL=""
[[ -n "$LINUX_ARCH" ]] && NODE_TARBALL="$(find "$HERE" -maxdepth 1 -name "node-v*-linux-$LINUX_ARCH.tar.xz" | head -1 || true)"
if [[ -n "$NODE_TARBALL" ]]; then
  nv="$(basename "$NODE_TARBALL" | sed -E 's/node-v([0-9.]+)-.*/\1/')"
  ndest="$(obd_dest /usr/local/lib)/obd-node-v$nv"
  if [[ ! -x "$ndest/bin/node" ]]; then
    mkdir -p "$ndest"
    tar -xJf "$NODE_TARBALL" -C "$ndest" --strip-components=1
    chmod +x "$ndest"/bin/* 2>/dev/null || true
  fi
  for b in node npm npx corepack; do
    [[ -x "$ndest/bin/$b" ]] || continue
    if [[ -n "${OBD_DEST_PREFIX:-}" ]]; then ln -sfn "$ndest/bin/$b" "$(obd_dest /usr/local/bin)/$b"
    elif [[ -w /usr/local/bin ]] || sudo -n true 2>/dev/null; then sudo ln -sfn "$ndest/bin/$b" "/usr/local/bin/$b" 2>/dev/null || ln -sfn "$ndest/bin/$b" "$HOME/.local/bin/$b"
    else mkdir -p "$HOME/.local/bin"; ln -sfn "$ndest/bin/$b" "$HOME/.local/bin/$b"; fi
  done
  obd_ok "Node v$nv → $ndest"
  node_bin="$ndest/bin/node"
else
  node_bin=""
  obd_warn "Node Linux tarball not in kit — pi needs a Linux node; install manually"
fi

# --- pi (cross-platform node app; tree comes straight from the kit) -----------
if [[ -d "$WORK/home/.pi" ]]; then
  pi_dest="$(obd_dest "${OBD_HOME:-$HOME}")/.pi"
  obd_step "Installing Pi → $pi_dest"
  set_aside "$pi_dest"
  copy_dir "$WORK/home/.pi" "$pi_dest"
  pl="$(obd_dest "${OBD_HOME:-$HOME}")/.local/bin/pi"
  mkdir -p "$(dirname "$pl")"; ln -sfn ../../.pi/agent/bin/pi "$pl"
  chmod +x "$pi_dest/agent/bin/pi" 2>/dev/null || true
  obd_ok "Pi launcher → $pl"
else
  pl=""
  obd_warn "Pi tree not found in kit"
fi

# --- claude -------------------------------------------------------------------
if [[ -x "$HERE/claude-linux-$LINUX_ARCH" ]]; then
  cldest="$(install_bin "$HERE/claude-linux-$LINUX_ARCH" claude)"
  obd_ok "claude CLI → $cldest"
else
  cldest=""
  obd_warn "claude Linux binary not in kit"
fi
if [[ -d "$WORK/home/.claude" ]]; then
  ch_dest="$(obd_dest "${CLAUDE_HOME_PATH:-$HOME/.claude}")"
  set_aside "$ch_dest"; copy_dir "$WORK/home/.claude" "$ch_dest"
  obd_ok "claude data → $ch_dest"
fi

# --- opencode -----------------------------------------------------------------
if [[ -x "$HERE/opencode-linux-$LINUX_ARCH" ]]; then
  ocbdest="$(install_bin "$HERE/opencode-linux-$LINUX_ARCH" opencode)"
  obd_ok "opencode CLI → $ocbdest"
else
  ocbdest=""
  obd_warn "opencode Linux binary not in kit"
fi
for pair in "home/.config/opencode:${OPENCODE_CONFIG_PATH:-$HOME/.config/opencode}" \
            "home/.local/share/opencode:${OPENCODE_SHARE_PATH:-$HOME/.local/share/opencode}" \
            "home/.local/state/opencode:${OPENCODE_STATE_PATH:-$HOME/.local/state/opencode}"; do
  src_rel="${pair%%:*}"; dest_t="${pair#*:}"
  [[ -d "$WORK/$src_rel" ]] || continue
  d="$(obd_dest "$dest_t")"
  set_aside "$d"; copy_dir "$WORK/$src_rel" "$d"
  obd_ok "$(basename "$src_rel") → $d"
done

# --- PATH + OLLAMA_HOST wiring ------------------------------------------------
obd_env="$(obd_dest "${OBD_HOME:-$HOME}")/.obd-devcontainer.sh"
{
  echo '# added by Ollama Backup Deluxe (devcontainer restore)'
  echo 'export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"'
  echo "export OLLAMA_HOST=\"$OLLAMA_HOST\""
} > "$obd_env"
for rc in .bashrc .zshrc; do
  rcfile="$(obd_dest "${OBD_HOME:-$HOME}")/$rc"
  [[ -f "$rcfile" ]] || printf '# created by Ollama Backup Deluxe\n' > "$rcfile"
  if ! grep -q ".obd-devcontainer.sh" "$rcfile" 2>/dev/null; then
    printf '\n[ -f "$HOME/.obd-devcontainer.sh" ] && . "$HOME/.obd-devcontainer.sh"\n' >> "$rcfile"
  fi
done
obd_ok "Env wired: OLLAMA_HOST=$OLLAMA_HOST (sourced from .bashrc/.zshrc)"

# --- verification -------------------------------------------------------------
obd_step "Verifying devcontainer toolset…"
dc_pass=0; dc_fail=0
dc_chk() { if [[ "$2" == "0" ]]; then printf '  ✓ %s %s\n' "$1" "${3:-}"; dc_pass=$((dc_pass+1));
           else printf '  ✗ %s %s\n' "$1" "${3:-}"; dc_fail=$((dc_fail+1)); fi; }
v_run() { # v_run <label> <binary> — exec version only when it can run here
  local label="$1" bin="$2" v=""
  if [[ "$IS_LINUX" == "1" || -n "${OBD_DC_FORCE_EXEC:-}" ]]; then
    v="$("$bin" --version 2>/dev/null | head -1 | awk '{print $1}')" || v=""
    if [[ -n "$v" ]]; then dc_chk "$label" 0 "$v"; else dc_chk "$label" 1 "did not run"; fi
  else
    [[ -x "$bin" ]] && dc_chk "$label" 0 "placed (exec check skipped on $(uname -s))" \
                    || dc_chk "$label" 1 "missing"
  fi
}
[[ -n "$odest" && -x "$odest" ]] && v_run "ollama" "$odest" || dc_chk "ollama" 1 "not installed"
[[ -n "$pl" && -x "$pl" ]] && v_run "pi" "$pl" || dc_chk "pi" 1 "not installed"
[[ -n "$cldest" && -x "$cldest" ]] && v_run "claude" "$cldest" || dc_chk "claude" 1 "not installed"
[[ -n "$ocbdest" && -x "$ocbdest" ]] && v_run "opencode" "$ocbdest" || dc_chk "opencode" 1 "not installed"
[[ -n "$node_bin" && -x "$node_bin" ]] && v_run "node" "$node_bin" || dc_chk "node" 1 "not installed"
if curl -fsS --max-time 4 "$OLLAMA_HOST/api/version" >/dev/null 2>&1; then
  dc_chk "host ollama reachable" 0 "$OLLAMA_HOST"
else
  printf '  ~ %-42s %s\n' "host ollama reachable" "NOT YET — $OLLAMA_HOST (expose Ollama on the host: OLLAMA_HOST=0.0.0.0 / app network setting; toolset install is still complete)"
fi

echo
if (( dc_fail > 0 )); then
  obd_err "Devcontainer restore: $dc_pass passed, $dc_fail FAILED"
  exit 1
fi
obd_ok "Devcontainer restore complete — try: ollama list && ollama launch pi"
