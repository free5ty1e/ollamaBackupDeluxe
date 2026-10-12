#!/usr/bin/env bash
# verify.sh — check that the inference stack is installed and consistent.
# Standalone audit of the current machine, or --manifest <manifest.env> to
# compare a restored install against what the backup contained.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # resolved at runtime next to this script
source "$HERE/common.sh"
cd "$HERE/.." || exit 1
require_macos

MANIFEST="" SKIP_CLI=0 EXPECT_SERVER=0 ALLOW_OFFLINE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)         MANIFEST="$2"; shift 2 ;;
    --skip-cli-symlink) SKIP_CLI=1; shift ;;
    --expect-server)    EXPECT_SERVER=1; shift ;;
    --allow-offline)    ALLOW_OFFLINE=1; shift ;;
    -h|--help)          grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) obd_die "Unknown argument: $1 (see --help)" ;;
  esac
done

if [[ -n "$MANIFEST" ]]; then
  [[ -f "$MANIFEST" ]] || obd_die "Manifest not found: $MANIFEST"
  # shellcheck disable=SC1090
  source "$MANIFEST"
fi

PASS=0; FAIL=0
chk()  { # chk <label> <result 0|1> [detail]
  local label="$1" res="$2" detail="${3:-}"
  if [[ "$res" == "0" ]]; then
    printf '  %s %-42s %s\n' "$(obd_color '32' '✓')" "$label" "$detail"; PASS=$((PASS+1))
  else
    printf '  %s %-42s %s\n' "$(obd_color '31' '✗')" "$label" "$detail"; FAIL=$((FAIL+1))
  fi
}
warn() { printf '  %s %-42s %s\n' "$(obd_color '33' '~')" "$1" "$2"; }

echo "Ollama Backup Deluxe — verification"
echo

# --- Ollama app ---
if [[ -d "$OBD_OLLAMA_APP" ]]; then
  ocli="$OBD_OLLAMA_APP/Contents/Resources/ollama"
  if [[ -x "$ocli" ]]; then
    v="$("$ocli" --version 2>/dev/null | head -1 | awk '{print $NF}' | tr -d '"')"
    exp="${OLLAMA_VERSION:-}"
    if [[ -n "$exp" && "$exp" != "unknown" && -n "$v" && "$v" != "$exp" ]]; then
      chk "Ollama app binary" 1 "version '$v' != manifest '$exp'"
    else
      chk "Ollama app binary" 0 "${v:-executable} ($OBD_OLLAMA_APP)"
    fi
  else
    chk "Ollama app binary" 1 "CLI binary missing in bundle"
  fi
else
  chk "Ollama app bundle" 1 "$OBD_OLLAMA_APP not found"
fi

# --- Ollama CLI symlink ---
if [[ "$SKIP_CLI" == "1" ]]; then
  warn "Ollama CLI symlink" "skipped (--skip-cli-symlink)"
elif [[ -e "$OBD_OLLAMA_CLI" ]]; then
  chk "Ollama CLI symlink" 0 "$OBD_OLLAMA_CLI"
else
  chk "Ollama CLI symlink" 1 "$OBD_OLLAMA_CLI missing"
fi

# --- Ollama data + models ---
if [[ -d "$OBD_OLLAMA_HOME" ]]; then
  chk "Ollama data home" 0 "$OBD_OLLAMA_HOME"
  if [[ -d "$OBD_OLLAMA_HOME/models" ]]; then
    n="$(obd_model_list "$OBD_OLLAMA_HOME" | grep -c . || true)"
    blobs="$(find "$OBD_OLLAMA_HOME/models/blobs" -type f 2>/dev/null | wc -l | tr -d ' ')"
    exp="${MODELS_COUNT:-}"
    if [[ -n "$exp" && "$n" != "$exp" ]]; then
      chk "Model registry" 1 "$n models, manifest expects $exp"
    else
      chk "Model registry" 0 "$n models, $blobs blobs"
    fi
  else
    chk "Model registry" 1 "models/ directory missing"
  fi
  if [[ -f "$OBD_OLLAMA_HOME/id_ed25519" ]]; then
    chk "Ollama identity keys" 0 "id_ed25519 present"
  else
    warn "Ollama identity keys" "id_ed25519 not found (regenerable)"
  fi
else
  chk "Ollama data home" 1 "$OBD_OLLAMA_HOME not found"
fi

# --- App-support data ---
if [[ -d "$OBD_OLLAMA_APP_SUPPORT" ]]; then
  if [[ -f "$OBD_OLLAMA_APP_SUPPORT/db.sqlite" ]]; then
    chk "Ollama app database" 0 "db.sqlite present"
  else
    warn "Ollama app database" "db.sqlite not found (recreated on first run)"
  fi
elif [[ -n "${OLLAMA_APP_SUPPORT_PATH:-}" ]]; then
  chk "Ollama app database" 1 "$OBD_OLLAMA_APP_SUPPORT missing"
fi

# --- Pi ---
if [[ -d "$OBD_PI_HOME" ]]; then
  chk "Pi home" 0 "$OBD_PI_HOME"
  pl="$OBD_PI_HOME/agent/bin/pi"
  if [[ -x "$pl" ]]; then
    pv="$("$pl" --version 2>/dev/null | head -1)"
    exp="${PI_VERSION:-}"
    if [[ -n "$exp" && "$exp" != "unknown" && -n "$pv" && "$pv" != "$exp" ]]; then
      chk "Pi launcher" 1 "version '$pv' != manifest '$exp'"
    else
      chk "Pi launcher" 0 "${pv:-runs}"
    fi
  else
    chk "Pi launcher" 1 "$pl missing or not executable"
  fi
  if [[ -f "$OBD_PI_HOME/agent/install/current-version" ]]; then
    cv="$(cat "$OBD_PI_HOME/agent/install/current-version")"
    if [[ -d "$OBD_PI_HOME/agent/install/releases/$cv" ]]; then
      chk "Pi managed release" 0 "v$cv installed"
    else
      chk "Pi managed release" 1 "release dir for v$cv missing"
    fi
  else
    chk "Pi managed release" 1 "install/current-version missing"
  fi
else
  chk "Pi home" 1 "$OBD_PI_HOME not found"
fi

# --- Node runtime ---
node_ok=1; node_detail=""
if command -v node >/dev/null 2>&1; then
  nv="$(node --version 2>/dev/null || true)"; node_ok=0; node_detail="on PATH ($nv)"
elif [[ -x "$OBD_BREW_PREFIX/opt/node/bin/node" ]]; then
  nv="$("$OBD_BREW_PREFIX/opt/node/bin/node" --version 2>/dev/null || true)"
  node_ok=0; node_detail="$OBD_BREW_PREFIX/opt/node/bin/node ($nv) — add to PATH"
elif [[ -n "${NODE_VERSION:-}" ]]; then
  node_detail="manifest expects Node ${NODE_VERSION}"
else
  node_detail="node not found"
fi
chk "Node runtime" "$node_ok" "$node_detail"

# --- Ollama server (only when expected) ---
if [[ "$EXPECT_SERVER" == "1" ]]; then
  if curl -fsS --max-time 3 http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
    chk "Ollama server" 0 "responding on 127.0.0.1:11434"
  else
    chk "Ollama server" 1 "not responding (is the app running?)"
  fi
elif [[ "$ALLOW_OFFLINE" == "1" ]]; then
  warn "Ollama server" "not checked (--allow-offline)"
fi

echo
if (( FAIL > 0 )); then
  obd_err "Verification: $PASS passed, $FAIL FAILED"
  exit 1
fi
obd_ok "Verification: all $PASS checks passed"
