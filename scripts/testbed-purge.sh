#!/usr/bin/env bash
# testbed-purge.sh — remove everything the restore installs, to simulate a
# fresh OS on a test machine (e.g. an M1 Max) before rehearsing an offline
# restore. DANGEROUS BY DESIGN: this deletes ollama + ALL its model data,
# pi, claude, opencode, and the node runtime chain.
#
# Modes:
#   (default)          dry-run: list exactly what would be removed (with sizes)
#   --yes              actually purge
#   --audit            print the post-purge component audit (paste back for review)
#   --skip-brew        leave Homebrew node chain alone (purge user dirs only)
#
# Scope (all overridable via OBD_* — see scripts/common.sh):
#   Ollama: app bundle, CLI symlink, ~/.ollama (MODELS — gigabytes), app data, prefs
#   Pi: ~/.pi, launcher symlink
#   Claude: ~/.local/share/claude, ~/.claude, launcher
#   OpenCode: ~/.opencode, ~/.config/opencode, ~/.local/share, ~/.local/state, ~/.cache
#   Node: brew uninstall of node + its dependency chain, or direct Cellar/opt/bin removal
# NOT touched: Homebrew itself, other formulae, other ~/.config apps, shell rc files,
# user documents. The backup kit must already exist and be validated before running this.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/common.sh"
require_macos

MODE="dryrun"   # dryrun | purge | audit
SKIP_BREW=0
for arg in "$@"; do
  case "$arg" in
    --yes)      MODE="purge" ;;
    --audit)    MODE="audit" ;;
    --skip-brew) SKIP_BREW=1 ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) obd_die "Unknown argument: $arg (see --help)" ;;
  esac
done

# safety: refuse to operate on absurd roots
for v in "$OBD_HOME" "$OBD_OLLAMA_HOME" "$OBD_PI_HOME" "$OBD_CLAUDE_SHARE" "$OBD_OPENCODE_HOME"; do
  [[ "$v" == "/" || -z "$v" ]] && obd_die "refusing to run: unsafe path '$v' (check OBD_* overrides)"
done

# node chain formulae (target machine's brew, when the prefix matches)
BREW_IS_REAL=0
if command -v brew >/dev/null 2>&1 && [[ "$(brew --prefix 2>/dev/null)" == "$OBD_BREW_PREFIX" ]]; then
  BREW_IS_REAL=1
fi
NODE_CHAIN=""
if [[ "$BREW_IS_REAL" == "1" ]]; then
  NODE_CHAIN="$(brew deps node 2>/dev/null | tr '\n' ' ' || true)"
  NODE_CHAIN="node $NODE_CHAIN"
fi

targets=()   # "label|path"
targets+=("Ollama app|$OBD_OLLAMA_APP")
targets+=("Ollama CLI symlink|$OBD_OLLAMA_CLI")
targets+=("Ollama data (MODELS)|$OBD_OLLAMA_HOME")
targets+=("Ollama app data|$OBD_OLLAMA_APP_SUPPORT")
targets+=("Pi home|$OBD_PI_HOME")
targets+=("Pi launcher|$OBD_PI_LAUNCHER")
targets+=("Claude runtime|$OBD_CLAUDE_SHARE")
targets+=("Claude data|$OBD_CLAUDE_HOME")
targets+=("Claude launcher|$OBD_CLAUDE_LAUNCHER")
targets+=("OpenCode home|$OBD_OPENCODE_HOME")
targets+=("OpenCode config|$OBD_OPENCODE_CONFIG")
targets+=("OpenCode sessions|$OBD_OPENCODE_SHARE")
targets+=("OpenCode state|$OBD_OPENCODE_STATE")
targets+=("OpenCode cache|$OBD_HOME/.cache/opencode")
if [[ "$SKIP_BREW" == "0" ]]; then
  if [[ "$BREW_IS_REAL" == "1" ]]; then
    targets+=("Node chain (brew uninstall)|brew:$NODE_CHAIN")
  else
    targets+=("Node Cellar (direct)|$OBD_BREW_PREFIX/Cellar/node")
    targets+=("node_modules (direct)|$OBD_BREW_PREFIX/lib/node_modules")
  fi
fi

exists() { [[ -e "$1" || -L "$1" ]]; }

if [[ "$MODE" == "audit" ]]; then
  echo "=== OBD testbed audit — $(hostname) — $(uname -m) — macOS $(sw_vers -productVersion) ==="
  echo "binaries:"
  for b in ollama node pi claude opencode; do
    p="$(command -v "$b" 2>/dev/null || true)"
    v=""
    [[ -n "$p" ]] && v="$("$p" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
    printf '  %-10s %s %s\n' "$b" "${p:-ABSENT}" "${v:+(v$v)}"
  done
  echo "paths:"
  printf '  %-24s %s\n' "Ollama app" "$(exists "$OBD_OLLAMA_APP" && echo PRESENT || echo absent)"
  printf '  %-24s %s\n' "Ollama CLI symlink" "$(exists "$OBD_OLLAMA_CLI" && echo PRESENT || echo absent)"
  # shellcheck disable=SC2086
  printf '  %-24s %s\n' "Ollama data home" "$(exists "$OBD_OLLAMA_HOME" && echo "PRESENT ($(human_size $(( $(dir_size_kb "$OBD_OLLAMA_HOME") * 1024 ))))" || echo absent)"
  printf '  %-24s %s\n' "Ollama app data" "$(exists "$OBD_OLLAMA_APP_SUPPORT" && echo PRESENT || echo absent)"
  printf '  %-24s %s\n' "Ollama API" "$(curl -fsS --max-time 2 http://127.0.0.1:11434/api/version >/dev/null 2>&1 && echo UP || echo down)"
  printf '  %-24s %s\n' "Pi home" "$(exists "$OBD_PI_HOME" && echo PRESENT || echo absent)"
  printf '  %-24s %s\n' "Claude runtime+data" "$(exists "$OBD_CLAUDE_SHARE" && echo PRESENT || echo absent) / $(exists "$OBD_CLAUDE_HOME" && echo PRESENT || echo absent)"
  printf '  %-24s %s\n' "OpenCode home/config" "$(exists "$OBD_OPENCODE_HOME" && echo PRESENT || echo absent) / $(exists "$OBD_OPENCODE_CONFIG" && echo PRESENT || echo absent)"
  if [[ "$BREW_IS_REAL" == "1" ]]; then
    printf '  %-24s %s\n' "brew node Cellar" "$(exists "$OBD_BREW_PREFIX/Cellar/node" && echo PRESENT || echo absent)"
    printf '  %-24s %s\n' "brew lib/node_modules" "$(exists "$OBD_BREW_PREFIX/lib/node_modules" && echo PRESENT || echo absent)"
  else
    printf '  %-24s %s\n' "brew" "not on PATH / prefix mismatch"
  fi
  local_procs="$(pgrep -l Ollama 2>/dev/null | tr '\n' ' ')"
  echo "ollama processes: ${local_procs:-none}"
  exit 0
fi

echo "=== OBD testbed purge — mode: $MODE ==="
echo "Machine: $(hostname) ($(uname -m), macOS $(sw_vers -productVersion))"
echo "Ollama processes will be stopped. THE FOLLOWING WILL BE PERMANENTLY DELETED:"
total_kb=0
for t in "${targets[@]}"; do
  label="${t%%|*}"; path="${t#*|}"
  if [[ "$path" == brew:* ]]; then
    printf '  - %-24s %s\n' "$label" "${path#brew:}"
    continue
  fi
  if exists "$path"; then
    kb=$(dir_size_kb "$path"); total_kb=$((total_kb + kb))
    printf '  - %-24s %-70s (%s)\n' "$label" "$path" "$(human_size $((kb * 1024)))"
  fi
done
echo "Total: $(human_size $((total_kb * 1024)))"
[[ "$MODE" == "dryrun" ]] && { echo; echo "DRY RUN — nothing deleted. Re-run with --yes to purge, or --audit to check state."; exit 0; }

printf '\nType PURGE to permanently delete the above: '
read -r reply
[[ "$reply" == "PURGE" ]] || obd_die "aborted (type PURGE to confirm)"

obd_quit_ollama

for t in "${targets[@]}"; do
  label="${t%%|*}"; path="${t#*|}"
  if [[ "$path" == brew:* ]]; then
    if [[ "$BREW_IS_REAL" == "1" ]]; then
      obd_step "brew uninstall node chain…"
      # shellcheck disable=SC2086  # word splitting of the formula list is intended
      brew uninstall --ignore-dependencies --zap ${path#brew:} >/dev/null 2>&1 || obd_warn "brew uninstall had failures (continuing)"
      for f in ${path#brew:}; do
        exists "$OBD_BREW_PREFIX/Cellar/$f" && { rm -rf "$OBD_BREW_PREFIX/Cellar/$f"; obd_ok "removed leftover Cellar/$f"; }
        exists "$OBD_BREW_PREFIX/opt/$f" && rm -rf "$OBD_BREW_PREFIX/opt/$f"
      done
      for b in node npm npx corepack; do
        [[ -L "$OBD_BREW_PREFIX/bin/$b" ]] && rm -f "$OBD_BREW_PREFIX/bin/$b"
      done
    fi
    continue
  fi
  if exists "$path"; then
    if rm -rf "$path" 2>/dev/null; then
      obd_ok "removed $label ($path)"
    else
      obd_err "could not remove $path — macOS may require permission (drag /Applications/Ollama.app to Trash manually, or grant App Management to your terminal), then re-run"
    fi
  fi
done
# ollama prefs
rm -f "$OBD_HOME/Library/Preferences/com.ollama."*.plist 2>/dev/null || true

echo
obd_step "Post-purge audit (--audit to re-run):"
for b in ollama node pi claude opencode; do
  if command -v "$b" >/dev/null 2>&1; then
    obd_warn "$b still on PATH: $(command -v "$b")"
  else
    obd_ok "$b gone"
  fi
done
obd_info "Shell rc PATH lines were left alone (harmless; restore gap-fills). Rehearse the restore next: start-webapp.sh from the release bundle."
