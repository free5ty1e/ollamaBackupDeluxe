#!/usr/bin/env bash
# build-release.sh — assemble the portable release bundle (see docs/plans §4b).
# Output: dist/ollama-backup-deluxe-v<version>-macos.zip (+ .sha256)
# The bundle runs on a fresh macOS with zero internet: it ships its own 7zz
# (both arches) and official Node tarballs (both arches).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # resolved at runtime next to this script
source "$HERE/common.sh"
cd "$HERE/.." || exit 1

VERSION="0.0.0"
OUT_DIR="$OBD_PROJECT_DIR/dist"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --out)     OUT_DIR="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) obd_die "Unknown argument: $1" ;;
  esac
done
obd_require_7zz
mkdir -p "$OUT_DIR"

NAME="ollama-backup-deluxe-v${VERSION}-macos"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/obd-release.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
REL="$STAGE/$NAME"
mkdir -p "$REL/bin" "$REL/runtime" "$REL/docs"

obd_step "Staging project files…"
cp -R "$OBD_PROJECT_DIR/scripts" "$OBD_PROJECT_DIR/webapp" "$REL/"
cp "$OBD_PROJECT_DIR/start-webapp.sh" "$REL/" 2>/dev/null || obd_die "start-webapp.sh missing"
cp -R "$OBD_PROJECT_DIR/llm-wiki" "$REL/llm-wiki" 2>/dev/null || true
cp -R "$OBD_PROJECT_DIR/docs" "$REL/docs" 2>/dev/null || true
cp "$OBD_PROJECT_DIR/README.md" "$OBD_PROJECT_DIR/AGENTS.md" "$OBD_PROJECT_DIR/LICENSE" "$REL/" 2>/dev/null || true
rm -rf "$REL/scripts/.tmp" 2>/dev/null || true
printf '%s\n' "$VERSION" > "$REL/VERSION"

# --- 7zz: official mac builds are universal (one binary, both arches) ---
acquire_7zz() { # acquire_7zz <output-path>
  local out="$1"
  local url vnum tag api_json
  api_json="$(curl -fsSL --max-time 30 https://api.github.com/repos/ip7z/7zip/releases/latest || true)"
  tag="$(printf '%s' "$api_json" | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/' || true)"
  [[ -n "$tag" ]] || obd_die "cannot determine latest 7-Zip release"
  vnum="${tag//./}"
  url="https://github.com/ip7z/7zip/releases/download/$tag/7z${vnum}-mac.tar.xz"
  local t; t="$(mktemp -d)"
  curl -fL --retry 3 -o "$t/7z.tar.xz" "$url"
  tar -xJf "$t/7z.tar.xz" -C "$t"
  mv "$t/7zz" "$out"; rm -rf "$t"
  chmod +x "$out"; xattr -dr com.apple.quarantine "$out" 2>/dev/null || true
}

obd_step "Bundling universal 7zz…"
if lipo -info "$OBD_7ZZ" 2>/dev/null | grep -q x86_64 && lipo -info "$OBD_7ZZ" 2>/dev/null | grep -q arm64; then
  cp "$OBD_7ZZ" "$REL/bin/7zz"
else
  acquire_7zz "$REL/bin/7zz"
fi
chmod +x "$REL/bin/7zz"

# --- Node runtime tarballs (both arches) ---
obd_step "Bundling official Node tarballs (both architectures)…"
NV="$(node --version 2>/dev/null | sed 's/^v//' || true)"
[[ -n "$NV" ]] || obd_die "node not found on PATH (needed to determine version)"
for arch in arm64 x64; do
  f="node-v${NV}-darwin-${arch}.tar.xz"
  cached="$OBD_CACHE_DIR/node-dist/$f"
  if [[ ! -s "$cached" ]]; then
    mkdir -p "$OBD_CACHE_DIR/node-dist"
    curl -fL --retry 3 -o "$cached.part" "https://nodejs.org/dist/v${NV}/$f"
    mv "$cached.part" "$cached"
  fi
  cp "$cached" "$REL/runtime/$f"
done

obd_step "Creating zip…"
( cd "$STAGE" && zip -qry "$OUT_DIR/$NAME.zip" "$NAME" )
sha256_file "$OUT_DIR/$NAME.zip" > "$OUT_DIR/$NAME.zip.sha256"
obd_ok "Release bundle: $OUT_DIR/$NAME.zip ($(human_size "$(wc -c < "$OUT_DIR/$NAME.zip" | tr -d ' ')"))"
obd_info "Contents: scripts, webapp, llm-wiki, docs, 7zz (arm64+x64), Node $NV tarballs (arm64+x64)"
