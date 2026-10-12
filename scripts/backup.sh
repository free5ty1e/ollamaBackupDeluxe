#!/usr/bin/env bash
# backup.sh — create a fully offline-restorable .7z backup kit of the local
# inference stack (Ollama + Pi + Node runtime + this tool's restore kit).
#
# Usage:
#   backup.sh --dest <dir> [--name <name>] [--level 0-9] [--no-node-dist]
#             [--no-logs] [--exclude-models] [--no-quit] [--dry-run] [--yes]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # resolved at runtime next to this script
source "$HERE/common.sh"
cd "$HERE/.." || exit 1
require_macos

DEST_DIR="" NAME="" LEVEL=5 NO_NODE_DIST=0 NO_LOGS=0 EXCLUDE_MODELS=0 NO_QUIT=0 DRY_RUN=0
[[ "${OBD_NO_QUIT:-0}" == "1" ]] && NO_QUIT=1   # test/sandbox guard
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)           DEST_DIR="$2"; shift 2 ;;
    --name)           NAME="$2"; shift 2 ;;
    --level)          LEVEL="$2"; shift 2 ;;
    --no-node-dist)   NO_NODE_DIST=1; shift ;;
    --no-logs)        NO_LOGS=1; shift ;;
    --exclude-models) EXCLUDE_MODELS=1; shift ;;
    --no-quit)        NO_QUIT=1; shift ;;
    --dry-run)        DRY_RUN=1; shift ;;
    --yes|-y)         shift ;;
    -h|--help)        grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) obd_die "Unknown argument: $1 (see --help)" ;;
  esac
done

[[ "$LEVEL" =~ ^[0-9]$ ]] || obd_die "--level must be 0-9"
obd_check_path_arg "$DEST_DIR" "--dest"
[[ -d "$DEST_DIR" ]] || obd_die "Destination directory does not exist: $DEST_DIR"
DEST_DIR="$(cd "$DEST_DIR" && pwd)"
NAME="${NAME:-ollama-backup-$(date '+%Y%m%d-%H%M%S')}"
NAME="${NAME// /_}"
OUT_7Z="$DEST_DIR/$NAME.7z"
[[ "$OUT_7Z" != "$OBD_PROJECT_DIR"/* ]] || obd_warn "Writing backup inside the project directory"

obd_require_7zz
[[ -d "$OBD_OLLAMA_HOME" ]] || obd_die "Ollama data home not found: $OBD_OLLAMA_HOME"
[[ -d "$OBD_PI_HOME" ]] || obd_warn "Pi home not found: $OBD_PI_HOME (backup will omit it)"
[[ -d "$OBD_OLLAMA_APP" ]] || obd_warn "Ollama app not found: $OBD_OLLAMA_APP (backup will omit it)"

# ---------------------------------------------------------------------------
# Preflight: sizes + disk space
# ---------------------------------------------------------------------------
obd_step "Measuring source sizes…"
SIZE_MODELS_KB=$(dir_size_kb "$OBD_OLLAMA_HOME/models")
SIZE_OLLAMA_KB=$(dir_size_kb "$OBD_OLLAMA_HOME")
SIZE_PI_KB=$(dir_size_kb "$OBD_PI_HOME")
SIZE_APP_KB=$(dir_size_kb "$OBD_OLLAMA_APP")
SIZE_SUPPORT_KB=$(dir_size_kb "$OBD_OLLAMA_APP_SUPPORT")
obd_detect_node
SIZE_BREW_KB=0
if [[ "$OBD_NODE_MODE" == "brew" ]]; then
  for f in $OBD_NODE_FORMULAE; do
    SIZE_BREW_KB=$(( SIZE_BREW_KB + $(dir_size_kb "$OBD_BREW_PREFIX/Cellar/$f") ))
  done
fi
NODE_DIST_FILE=""
if [[ "$NO_NODE_DIST" == "0" && -n "$OBD_NODE_VERSION" ]]; then
  ver="${OBD_NODE_VERSION#v}"
  cand="$OBD_CACHE_DIR/node-dist/node-v${ver}-darwin-$([[ $(uname -m) == arm64 ]] && echo arm64 || echo x64).tar.xz"
  [[ -s "$cand" ]] && NODE_DIST_FILE="$cand"
fi
TOTAL_KB=$(( SIZE_OLLAMA_KB + SIZE_PI_KB + SIZE_APP_KB + SIZE_SUPPORT_KB + SIZE_BREW_KB ))
[[ -n "$NODE_DIST_FILE" ]] && TOTAL_KB=$(( TOTAL_KB + $(wc -c < "$NODE_DIST_FILE" | tr -d ' ') / 1024 ))
FREE_KB=$(df -k "$DEST_DIR" | awk 'NR==2{print $4}')
obd_info "Estimated source: $(human_size $(( TOTAL_KB * 1024 )))  |  Free at destination: $(human_size $(( FREE_KB * 1024 )))"
if (( FREE_KB * 110 / 100 < TOTAL_KB )); then
  obd_die "Not enough free space at destination (need ~$(human_size $(( TOTAL_KB * 1024 ))) + margin)."
fi
if (( EXCLUDE_MODELS == 0 )); then
  obd_info "Models: $(obd_model_list "$OBD_OLLAMA_HOME" | wc -l | tr -d ' ') ($(human_size $(( SIZE_MODELS_KB * 1024 ))))"
fi

# ---------------------------------------------------------------------------
# Component inventory
# ---------------------------------------------------------------------------
obd_detect_node
NODE_FORMULAE="${OBD_NODE_FORMULAE:-}"
PI_VERSION="$("$OBD_PI_HOME/agent/bin/pi" --version 2>/dev/null | head -1 || true)"
OLLAMA_VERSION="$("$OBD_OLLAMA_APP/Contents/Resources/ollama" --version 2>/dev/null | head -1 | awk '{print $NF}' | tr -d '"' || true)"
HOSTNAME_STR=$(hostname)
MACOS_VER="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
ARCH="$(uname -m)"
CREATED_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
MODELS_LIST="$(obd_model_list "$OBD_OLLAMA_HOME")"

# ---------------------------------------------------------------------------
# Staging (symlinks — compressed through with 7zz -l; no data duplication)
# ---------------------------------------------------------------------------
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/obd-stage.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT INT TERM

mk_stage_tree() {
  mkdir -p "$STAGE/home" "$STAGE/Applications" "$STAGE/app-support" \
           "$STAGE/restore-kit" "$STAGE/project"
  [[ "$OBD_NODE_MODE" == "brew" ]] && mkdir -p "$STAGE/brew/Cellar"
  [[ -n "$NODE_DIST_FILE" ]] && mkdir -p "$STAGE/node-dist"
  # --- ~/.ollama (per-entry links: exclude cache, optional logs/models) ---
  mkdir -p "$STAGE/home/.ollama"
  local entry
  for entry in "$OBD_OLLAMA_HOME"/* "$OBD_OLLAMA_HOME"/.[!.]*; do
    [[ -e "$entry" ]] || continue
    entry="$(readlink -f "$entry")"; local base="${entry##*/}"
    case "$base" in
      cache)                                   continue ;;          # regenerable
      logs)    [[ "$NO_LOGS" == "1" ]] && continue ;;
      models)  [[ "$EXCLUDE_MODELS" == "1" ]] && continue ;;
    esac
    ln -s "$entry" "$STAGE/home/.ollama/$base"
  done
  # --- ~/.pi (skip install/staging = partial downloads) ---
  if [[ -d "$OBD_PI_HOME" ]]; then
    mkdir -p "$STAGE/home/.pi/agent/install"
    ln -s "$OBD_PI_HOME/agent/bin"         "$STAGE/home/.pi/agent/bin"
    for f in auth.json models.json models-store.json settings.json; do
      [[ -e "$OBD_PI_HOME/agent/$f" ]] && ln -s "$OBD_PI_HOME/agent/$f" "$STAGE/home/.pi/agent/$f"
    done
    for d in sessions npm; do
      [[ -d "$OBD_PI_HOME/agent/$d" ]] && ln -s "$OBD_PI_HOME/agent/$d" "$STAGE/home/.pi/agent/$d"
    done
    for f in current-version managed-install.json; do
      [[ -e "$OBD_PI_HOME/agent/install/$f" ]] && ln -s "$OBD_PI_HOME/agent/install/$f" "$STAGE/home/.pi/agent/install/$f"
    done
    [[ -d "$OBD_PI_HOME/agent/install/releases" ]] && ln -s "$OBD_PI_HOME/agent/install/releases" "$STAGE/home/.pi/agent/install/releases"
  fi
  # --- Ollama app + app support ---
  [[ -d "$OBD_OLLAMA_APP" ]] && ln -s "$OBD_OLLAMA_APP" "$STAGE/Applications/Ollama.app"
  [[ -d "$OBD_OLLAMA_APP_SUPPORT" ]] && ln -s "$OBD_OLLAMA_APP_SUPPORT" "$STAGE/app-support/Ollama"
  # --- brew node chain ---
  if [[ "$OBD_NODE_MODE" == "brew" ]]; then
    local f realver
    for f in $NODE_FORMULAE; do
      ln -s "$OBD_BREW_PREFIX/Cellar/$f" "$STAGE/brew/Cellar/$f"
      realver="$(readlink "$OBD_BREW_PREFIX/opt/$f" 2>/dev/null || true)"
      [[ -n "$realver" ]] && printf 'OPT_%s="%s"\n' "$(sanitized_key "$f")" "$realver" >> "$STAGE/opt-list.tmp"
    done
    # bin symlinks that point into the backed-up formulae (resolve targets so
    # relative links like ../lib/node_modules/... are matched by real path)
    : > "$STAGE/brew/bin-entries.txt"
    local b t rt
    while IFS= read -r -d '' b; do
      t="$(readlink "$b" 2>/dev/null || true)"; [[ -n "$t" ]] || continue
      rt="$(cd "$OBD_BREW_PREFIX/bin" 2>/dev/null && readlink -f "$b" 2>/dev/null || true)"
      local ok=0
      for f in $NODE_FORMULAE; do
        case "$rt" in
          "$OBD_BREW_PREFIX/Cellar/$f/"*|"$OBD_BREW_PREFIX/opt/$f/"*) ok=1; break ;;
        esac
        case "$t" in
          *"Cellar/$f/"*|*"/opt/$f/"*|*"lib/node_modules/"*) ok=1; break ;;
        esac
      done
      [[ "$ok" == "1" ]] && printf '%s\t%s\n' "${b##*/}" "$t" >> "$STAGE/brew/bin-entries.txt"
    done < <(find "$OBD_BREW_PREFIX/bin" -maxdepth 1 -type l -print0 2>/dev/null | sort -z)
  fi
  # --- node fallback tarball ---
  [[ -n "$NODE_DIST_FILE" ]] && cp "$NODE_DIST_FILE" "$STAGE/node-dist/"
  # --- restore kit (7zz + scripts + instructions) ---
  cp "$OBD_7ZZ" "$STAGE/restore-kit/7zz"
  chmod +x "$STAGE/restore-kit/7zz"
  cp "$OBD_SCRIPT_DIR/common.sh" "$OBD_SCRIPT_DIR/restore.sh" "$OBD_SCRIPT_DIR/verify.sh" "$STAGE/restore-kit/"
  write_restore_readme > "$STAGE/restore-kit/RESTORE-README.md"
  # --- project copy (self-contained kit) ---
  mkdir -p "$STAGE/project"
  cp -R "$OBD_PROJECT_DIR/scripts" "$OBD_PROJECT_DIR/webapp" "$STAGE/project/" 2>/dev/null || true
  for f in README.md AGENTS.md LICENSE; do [[ -f "$OBD_PROJECT_DIR/$f" ]] && cp "$OBD_PROJECT_DIR/$f" "$STAGE/project/"; done
  [[ -d "$OBD_PROJECT_DIR/llm-wiki" ]] && cp -R "$OBD_PROJECT_DIR/llm-wiki" "$STAGE/project/llm-wiki"
  [[ -d "$OBD_PROJECT_DIR/docs" ]] && cp -R "$OBD_PROJECT_DIR/docs" "$STAGE/project/docs"
}

write_manifest() {
  cat > "$STAGE/manifest.env" <<EOF
OBD_VERSION="$OBD_VERSION"
CREATED_UTC="$CREATED_UTC"
HOSTNAME="$HOSTNAME_STR"
ARCH="$ARCH"
MACOS_VERSION="$MACOS_VER"
OLLAMA_APP_PATH="$OBD_OLLAMA_APP"
OLLAMA_HOME_PATH="$OBD_OLLAMA_HOME"
OLLAMA_APP_SUPPORT_PATH="$OBD_OLLAMA_APP_SUPPORT"
PI_HOME_PATH="$OBD_PI_HOME"
PI_LAUNCHER_PATH="$OBD_PI_LAUNCHER"
OLLAMA_VERSION="${OLLAMA_VERSION:-unknown}"
PI_VERSION="${PI_VERSION:-unknown}"
NODE_MODE="$OBD_NODE_MODE"
NODE_VERSION="${OBD_NODE_VERSION:-}"
NODE_REAL="${OBD_NODE_REAL:-}"
NODE_FORMULAE="$NODE_FORMULAE"
BREW_PREFIX="$OBD_BREW_PREFIX"
MODELS_COUNT="$(printf '%s\n' "$MODELS_LIST" | grep -c . || true)"
INCLUDE_LOGS="$( [[ $NO_LOGS == 0 ]] && echo 1 || echo 0 )"
INCLUDE_NODE_DIST="$( [[ -n "$NODE_DIST_FILE" ]] && echo 1 || echo 0 )"
EXCLUDE_MODELS="$EXCLUDE_MODELS"
COMPRESS_LEVEL="$LEVEL"
SIZE_TOTAL_KB="$TOTAL_KB"
SIZE_MODELS_KB="$SIZE_MODELS_KB"
EOF
  [[ -f "$STAGE/opt-list.tmp" ]] && cat "$STAGE/opt-list.tmp" >> "$STAGE/manifest.env"

  cat > "$STAGE/MANIFEST.txt" <<EOF
=== Ollama Backup Deluxe — Backup Kit Manifest ===
Tool version      : $OBD_VERSION
Created           : $CREATED_UTC
Source host       : $HOSTNAME_STR
Architecture      : $ARCH
macOS             : $MACOS_VER

Ollama            : ${OLLAMA_VERSION:-unknown}   ($OBD_OLLAMA_APP)
Ollama data       : $OBD_OLLAMA_HOME  ($(human_size $(( SIZE_OLLAMA_KB * 1024 ))))
Ollama app data   : $OBD_OLLAMA_APP_SUPPORT
Pi                : ${PI_VERSION:-unknown}   ($OBD_PI_HOME)
Node              : ${OBD_NODE_VERSION:-none} ($OBD_NODE_MODE)

Models ($(printf '%s\n' "$MODELS_LIST" | grep -c . || true)) — total $(human_size $(( SIZE_MODELS_KB * 1024 ))):
$(printf '%s\n' "$MODELS_LIST" | sed 's/^/  - /' || echo "  (none)")

Options           : level=$LEVEL logs=$([[ $NO_LOGS == 0 ]] && echo included || echo excluded) \
node-dist=$([[ -n "$NODE_DIST_FILE" ]] && echo included || echo excluded) \
models=$([[ $EXCLUDE_MODELS == 1 ]] && echo EXCLUDED || echo included)

Restoring: see restore-kit/RESTORE-README.md — the archive contains its own 7zz,
restore scripts, and a copy of this project. No internet required.
EOF
}

write_restore_readme() {
  cat <<'EOF'
# Offline Restore — quick instructions

You are holding a complete, self-contained backup kit. **No internet is required.**

## Easiest (web app, needs Node — bundled in the release bundle)
1. Unzip the release bundle (ollama-backup-deluxe-vX-macos.zip)
2. Run `./start-webapp.sh` → click RESTORE → pick this .7z file → confirm

## Terminal (works with zero extra software — bash is built into macOS)
1. Extract this archive with the 7zz binary sitting next to this README:
       ./7zz x "<path-to-backup>.7z" -o/tmp/obd-kit
2. Run the restore script:
       bash /tmp/obd-kit/restore-kit/restore.sh --archive "<path-to-backup>.7z"
3. Wait for the verification report. Re-enable "Start at Login" for Ollama.

The restore script quits Ollama, renames any existing installs aside
(*.pre-restore-<timestamp>), reinstalls everything, recreates symlinks and the
Node runtime, starts Ollama, and verifies the model list matches this manifest.
EOF
}

# ---------------------------------------------------------------------------
# Go
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" == "1" ]]; then
  mk_stage_tree; write_manifest
  obd_ok "DRY RUN — staging built at $STAGE (kept for inspection)"; trap - EXIT
  obd_info "Would write: $OUT_7Z"; exit 0
fi

if obd_ollama_running && [[ "$NO_QUIT" == "0" ]]; then
  obd_quit_ollama; RESTART_OLLAMA=1
else
  RESTART_OLLAMA=0
fi

obd_step "Building staging tree…"
mk_stage_tree
write_manifest
[[ -f "$STAGE/manifest.env" ]] || obd_die "manifest.env missing after staging"

obd_step "Compressing (7z, level $LEVEL) → $OUT_7Z"
PART="$OUT_7Z.part.7z"
rm -f "$PART"
# NOTE: default 7zz behavior dereferences the staging symlinks (stores real
# file content under staging-relative paths) — no -l switch needed.
# Only pass top-level entries that exist.
ADD_ARGS=()
for e in home Applications app-support brew node-dist restore-kit project manifest.env MANIFEST.txt; do
  [[ -e "$STAGE/$e" ]] && ADD_ARGS+=("$e")
done
( cd "$STAGE" && "$OBD_7ZZ" a -mx="$LEVEL" -mmt=on -bso0 -bsp1 -y -- "$PART" "${ADD_ARGS[@]}" \
    2>&1 | tr '\r' '\n' | grep -v '^$' | sed -u 's/^/  7z: /' ) || {
  rm -f "$PART"; obd_die "7z compression failed"; }
[[ -s "$PART" ]] || obd_die "Compression produced no output"

mv "$PART" "$OUT_7Z"
sha256_file "$OUT_7Z" > "$OUT_7Z.sha256"
cp "$STAGE/MANIFEST.txt" "$DEST_DIR/$NAME.manifest.txt"

obd_ok "Backup complete:"
printf '    %s  (%s)\n' "$OUT_7Z" "$(human_size "$(wc -c < "$OUT_7Z" | tr -d ' ')")"
printf '    %s\n' "$OUT_7Z.sha256"
printf '    %s\n' "$DEST_DIR/$NAME.manifest.txt"

if [[ "$RESTART_OLLAMA" == "1" ]]; then
  obd_step "Restarting Ollama…"
  open -a "$(basename "$OBD_OLLAMA_APP" .app)" 2>/dev/null || open "$OBD_OLLAMA_APP" || true
fi
