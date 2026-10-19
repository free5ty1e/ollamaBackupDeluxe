#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2012  # common.sh resolved at runtime; blob names are controlled
# validate-backup.sh — thoroughly validate a backup kit WITHOUT restoring it.
#
# Checks (each reported ✓/✗/~):
#   1. sidecar presence (.sha256; .manifest.txt advisory)
#   2. SHA256 of the archive vs sidecar (hash-only or standard "hash  name" format)
#   3. full 7z integrity test (7zz t — every CRC)          [skipped with --quick]
#   4. manifest.env: required keys, MODELS_COUNT > 0, arch match (warn)
#   5. structural: required kit entries (app, data, harnesses, restore-kit, project)
#   6. content-addressed integrity: N smallest model blobs extracted and verified
#      against their sha256-<hash> names                    [skipped with --quick]
#   7. spot checks vs the live machine when present (ollama binary, model list)
#   8. devcontainer kit sidecar presence (advisory)
#
# Usage: validate-backup.sh --archive <kit.7z> [--quick] [--7zz <path>] [--yes]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/common.sh"
require_macos

ARCHIVE="" QUICK=0 NO_BLOBS=0 BLOB_SAMPLES=3
while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)  ARCHIVE="$2"; shift 2 ;;
    --quick)    QUICK=1; shift ;;
    --no-blobs) NO_BLOBS=1; shift ;;           # skip blob extraction entirely
    --blobs)    BLOB_SAMPLES="$2"; shift 2 ;;  # how many sample blobs to verify
    --7zz)      export OBD_KIT_7ZZ="$2"; shift 2 ;;
    --yes|-y)   shift ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) obd_die "Unknown argument: $1 (see --help)" ;;
  esac
done

obd_check_path_arg "$ARCHIVE" "--archive"
[[ -f "$ARCHIVE" ]] || obd_die "Archive not found: $ARCHIVE"
ARCHIVE="$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")"
obd_require_7zz
Z="$OBD_7ZZ"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/obd-validate.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

PASS=0; FAIL=0
chk()  { local l="$1" res="$2" d="${3:-}"
  if [[ "$res" == "0" ]]; then printf '  %s %-46s %s\n' "$(obd_color '32' '✓')" "$l" "$d"; PASS=$((PASS+1));
  else printf '  %s %-46s %s\n' "$(obd_color '31' '✗')" "$l" "$d"; FAIL=$((FAIL+1)); fi; }
adv()  { printf '  %s %-46s %s\n' "$(obd_color '33' '~')" "$1" "$2"; }

echo "Ollama Backup Deluxe — backup kit validation"
echo "  kit: $ARCHIVE ($(human_size "$(wc -c < "$ARCHIVE" | tr -d ' ')"))"
echo

# --- 1) sidecars --------------------------------------------------------------
BASE="${ARCHIVE%.7z}"
if [[ -f "$ARCHIVE.sha256" ]]; then
  chk "sha256 sidecar present" 0 "$ARCHIVE.sha256"
else
  chk "sha256 sidecar present" 1 "missing — cannot prove integrity later"
fi
if [[ -f "$BASE.manifest.txt" ]]; then
  chk "manifest sidecar present" 0 "$BASE.manifest.txt"
else
  adv "manifest sidecar" "not found (advisory — the full manifest lives inside the kit)"
fi

# --- 2) sha256 verification ---------------------------------------------------
if [[ -f "$ARCHIVE.sha256" ]]; then
  expected="$(awk '{print $1}' "$ARCHIVE.sha256" | head -1)"
  if [[ ${#expected} != 64 ]]; then
    chk "SHA256 sidecar format" 1 "not a sha256 hex digest"
  else
    obd_step "Computing archive SHA256 (reads the whole kit)…"
    actual="$(sha256_file "$ARCHIVE")"
    if [[ "$actual" == "$expected" ]]; then
      chk "SHA256 matches sidecar" 0 "${actual:0:16}…"
    else
      chk "SHA256 matches sidecar" 1 "expected ${expected:0:16}… got ${actual:0:16}…"
    fi
  fi
else
  adv "SHA256 verification" "skipped (no sidecar)"
fi

# --- 3) 7z integrity (every CRC) ----------------------------------------------
if [[ "$QUICK" == "1" ]]; then
  adv "7z integrity test (7zz t)" "skipped (--quick)"
else
  obd_step "Testing archive integrity — every CRC (this reads the whole kit)…"
  if "$Z" t -bso0 -bsp0 "$ARCHIVE" >/dev/null 2>&1; then
    chk "7z integrity test (7zz t)" 0 "all CRCs OK"
  else
    chk "7z integrity test (7zz t)" 1 "archive is corrupt"
  fi
fi

# --- 4) manifest.env ----------------------------------------------------------
menv="$WORK/manifest.env"
if "$Z" e -y -bso0 -ba -o"$WORK" "$ARCHIVE" manifest.env >/dev/null 2>&1 && [[ -s "$menv" ]]; then
  # shellcheck disable=SC1090
  source "$menv"
  ok=0
  for k in OBD_VERSION CREATED_UTC HOSTNAME ARCH OLLAMA_HOME_PATH OLLAMA_VERSION; do
    [[ -n "${!k:-}" ]] || { ok=1; break; }
  done
  chk "manifest.env complete" $ok "OBD ${OBD_VERSION:-?}, ${CREATED_UTC:-?}, host ${HOSTNAME:-?}"
  if [[ "${ARCH:-}" != "$(uname -m)" ]]; then
    adv "architecture" "kit built for ${ARCH:-?} — this machine is $(uname -m)"
  else
    chk "architecture matches this machine" 0 "$ARCH"
  fi
  mc="${MODELS_COUNT:-0}"
  if [[ "$mc" =~ ^[0-9]+$ ]] && (( mc > 0 )); then
    chk "model count recorded" 0 "$mc models"
  else
    chk "model count recorded" 1 "MODELS_COUNT='$mc'"
  fi
  chk "harness versions recorded" 0 "Ollama ${OLLAMA_VERSION:-?} · Pi ${PI_VERSION:-?} · Claude ${CLAUDE_VERSION:-none} · OpenCode ${OPENCODE_VERSION:-none}"
else
  chk "manifest.env extractable" 1 "not an OBD backup kit?"
fi

# --- 5) structural: required entries -----------------------------------------
obd_step "Checking kit structure…"
listing="$WORK/listing.txt"
"$Z" l -ba "$ARCHIVE" > "$listing" 2>/dev/null || true
missing=0; lines=""
for req in "manifest.env" "MANIFEST.txt" "home/.ollama/config.json" "home/.ollama/id_ed25519" \
           "Applications/Ollama.app/Contents/Resources/ollama" "home/.pi/agent/install/current-version" \
           "restore-kit/7zz" "restore-kit/restore.sh" "restore-kit/verify.sh" \
           "project/scripts/backup.sh" "project/webapp/server.js"; do
  grep -qF "$req" "$listing" || { missing=$((missing+1)); lines+="$req "; }
done
chk "required kit entries" $missing "${lines:-all present}"
for opt in "home/.local/share/claude/versions/" "home/.opencode/bin/opencode" "brew/Cellar/node/" "brew/lib-node-modules/" "node-dist/"; do
  if grep -qF "$opt" "$listing"; then chk "optional: $opt" 0 ""
  else adv "optional: $opt" "not in kit"; fi
done

# counts vs the live machine (when this kit's ollama home exists here)
LIVE_HOME="${OLLAMA_HOME_PATH:-$HOME/.ollama}"
if [[ -d "$LIVE_HOME/models/blobs" ]]; then
  kit_blobs="$(grep -cE "home/\.ollama/models/blobs/sha256-" "$listing" || true)"
  live_blobs="$(ls "$LIVE_HOME/models/blobs" 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$kit_blobs" == "$live_blobs" ]]; then
    chk "model blobs (kit vs live)" 0 "$kit_blobs / $live_blobs"
  else
    chk "model blobs (kit vs live)" 1 "kit $kit_blobs, live $live_blobs (new pulls since backup?)"
  fi
  # extract the (tiny) manifests tree and count real files — the flat listing
  # cannot distinguish dirs from files (no trailing slashes in -ba output)
  # 'x' preserves paths ('e' flattens); extract the whole manifests trees
  "$Z" x -y -bso0 -o"$WORK/lmf" "$ARCHIVE" "home/.ollama/models/manifests" "home/.ollama/models/manifests-v2" >/dev/null 2>&1 || true
  kit_mfs="$(cd "$WORK/lmf/home/.ollama/models" 2>/dev/null && find manifests manifests-v2 -type f 2>/dev/null | sort)"
  live_mfs="$(cd "$LIVE_HOME/models" 2>/dev/null && find manifests manifests-v2 -type f 2>/dev/null | sort)"
  # directional set comparison: kit MISSING live files = kit outdated (fail);
  # kit EXTRAS = harmless (ollama prunes/migrates; the kit is a snapshot) (warn)
  kmn="$(printf '%s\n' "$kit_mfs" | grep -c . || true)"
  if [[ -z "$live_mfs" ]]; then
    if [[ "$kmn" == "${MODELS_COUNT:-x}" ]]; then
      chk "model manifests (kit vs manifest)" 0 "$kmn files (no live install to compare)"
    else
      chk "model manifests (kit vs manifest)" 1 "$kmn files, manifest claims ${MODELS_COUNT:-?}"
    fi
  else
    live_extra="$(comm -13 <(printf '%s\n' "$kit_mfs") <(printf '%s\n' "$live_mfs") | head -3 | tr '\n' ' ')"
    kit_extra="$(comm -23 <(printf '%s\n' "$kit_mfs") <(printf '%s\n' "$live_mfs") | head -3 | tr '\n' ' ')"
    if [[ -n "$live_extra" ]]; then
      chk "model manifests (kit vs live)" 1 "kit is missing: ${live_extra}(new pulls since backup?)"
    elif [[ -n "$kit_extra" ]]; then
      adv "model manifests (kit vs live)" "kit has $kmn files (live pruned: $kit_extra) — harmless extra"
    else
      chk "model manifests (kit vs live)" 0 "$kmn files, names identical"
    fi
  fi
else
  adv "live comparisons" "$LIVE_HOME not present here (validating away from the source machine)"
fi

# --- 6) content-addressed blob samples ---------------------------------------
if [[ "$NO_BLOBS" == "1" ]]; then
  adv "blob content verification" "skipped (--no-blobs)"
elif [[ "$QUICK" == "1" ]]; then
  adv "blob content verification" "skipped (--quick)"
else
  obd_step "Verifying $BLOB_SAMPLES sample blobs against their sha256 names…"
  grep -E "home/\.ollama/models/blobs/sha256-" "$listing" | sort -k4 -n | head -"$BLOB_SAMPLES" |
    awk '{print $NF}' > "$WORK/samples.txt"
  bs_ok=0; bs_total=0; bs_bad=""
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    bs_total=$((bs_total+1))
    name="$(basename "$rel")"; hash="${name#sha256-}"
    "$Z" e -y -bso0 -o"$WORK" "$ARCHIVE" "$rel" >/dev/null 2>&1
    actual="$(sha256_file "$WORK/$name" 2>/dev/null)"
    if [[ "$actual" == "$hash" ]]; then bs_ok=$((bs_ok+1)); else bs_bad+=" $name"; fi
    rm -f "$WORK/$name"
  done < "$WORK/samples.txt"
  if (( bs_total > 0 && bs_ok == bs_total )); then
    chk "content-addressed blob samples" 0 "$bs_ok/$bs_total verified"
  else
    chk "content-addressed blob samples" 1 "verified $bs_ok/$bs_total; bad:${bs_bad:- none}"
  fi
fi

# --- 7) live spot checks ------------------------------------------------------
live_bin="${OLLAMA_APP_PATH:-/Applications/Ollama.app}/Contents/Resources/ollama"
if [[ -x "$live_bin" ]]; then
  "$Z" e -y -bso0 -o"$WORK" "$ARCHIVE" "Applications/Ollama.app/Contents/Resources/ollama" >/dev/null 2>&1
  if [[ -x "$WORK/ollama" ]]; then
    a="$(sha256_file "$WORK/ollama")"; b="$(sha256_file "$live_bin")"
    if [[ "$a" == "$b" ]]; then chk "ollama binary: kit vs live" 0 "${a:0:16}…"
    else chk "ollama binary: kit vs live" 1 "differs (app updated since backup?)"; fi
    rm -f "$WORK/ollama"
  else
    adv "ollama binary: kit vs live" "could not extract from kit"
  fi
else
  adv "ollama binary: kit vs live" "no live install on this machine"
fi

# --- 8) devcontainer kit (advisory) -------------------------------------------
if [[ -f "${BASE}-devcontainer.tar.gz" ]]; then
  chk "devcontainer kit sidecar" 0 "$(basename "${BASE}-devcontainer.tar.gz")"
else
  adv "devcontainer kit sidecar" "not found (was backup run with --no-devcontainer?)"
fi

# --- verdict -------------------------------------------------------------------
echo
if (( FAIL > 0 )); then
  obd_err "Validation: $PASS passed, $FAIL FAILED — do NOT rely on this kit"
  exit 1
fi
obd_ok "Validation: all $PASS checks passed — this kit is restorable (offline-capable)"
[[ -n "${CREATED_UTC:-}" ]] && obd_info "Kit was created ${CREATED_UTC} on ${HOSTNAME:-?} (OBD v${OBD_VERSION:-?})"
