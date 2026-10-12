#!/usr/bin/env bash
# shellcheck disable=SC2015  # _pass/_fail are side-effect-only, safe with && ||
# test-7zip.sh — 7-Zip mechanism probes: symlink dereference on `a`, `e -so`,
# multiple roots with `--`, and level flag handling.
SUITE_NAME="test-7zip"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$HERE/tests/lib/assert.sh"
source "$HERE/scripts/common.sh"

if ! obd_find_7zz; then
  echo "  SKIP (no 7zz available — run scripts/prerequisites.sh)"; exit 0
fi
Z="$OBD_7ZZ"
TMP="$HERE/tests/.tmp/test-7zip.$$"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

# --- fixture with a symlinked dir + symlinked file + real file ---
mkdir -p "$TMP/real/sub" "$TMP/stage"
echo "alpha" > "$TMP/real/a.txt"; echo "beta" > "$TMP/real/sub/b.txt"
echo "filedata" > "$TMP/real/f.txt"
ln -s "$TMP/real" "$TMP/stage/homelink"
ln -s "$TMP/real/f.txt" "$TMP/stage/filelink"
echo "top" > "$TMP/stage/top.txt"

# --- add: default must dereference symlinks into real content ---
( cd "$TMP/stage" && "$Z" a -mx=5 -bso0 -bse0 -y -- "$TMP/out.7z" homelink filelink top.txt )
assert_file_exists "$TMP/out.7z" "archive created"
listing="$("$Z" l -ba "$TMP/out.7z" 2>/dev/null || true)"
assert_contains "$listing" "homelink/a.txt" "dir symlink dereferenced (homelink/a.txt)"
assert_contains "$listing" "homelink/sub/b.txt" "nested dereference (homelink/sub/b.txt)"
assert_contains "$listing" "filelink" "file symlink included"
assert_not_contains "$listing" "real/" "no stray absolute paths"

# --- extract round trip ---
mkdir "$TMP/x"
"$Z" x -y -bso0 -bse0 -o"$TMP/x" "$TMP/out.7z"
assert_file_exists "$TMP/x/homelink/a.txt" "extracted homelink/a.txt"
assert_eq "$(cat "$TMP/x/homelink/a.txt")" "alpha" "content round trip: alpha"
assert_eq "$(cat "$TMP/x/homelink/sub/b.txt")" "beta" "content round trip: beta"

# --- e -so: read a single file out of the archive to stdout ---
so="$("$Z" e -y -bso0 -ba -so "$TMP/out.7z" top.txt)"
assert_eq "$so" "top" "e -so single-file stdout extraction"

# --- levels 0 and 9 both produce valid archives; compressible data must shrink ---
for i in $(seq 1 2000); do echo "compressible line $i with repeated pattern aaaaaaaaaaaaaaaaaaaa"; done > "$TMP/stage/homelink/big.txt"
for lvl in 0 9; do
  ( cd "$TMP/stage" && "$Z" a -mx=$lvl -bso0 -bse0 -y -- "$TMP/l$lvl.7z" homelink top.txt )
  assert_cmd_ok "archive at level $lvl is valid" "$Z" t "$TMP/l$lvl.7z"
done
sz0=$(wc -c < "$TMP/l0.7z" | tr -d ' '); sz9=$(wc -c < "$TMP/l9.7z" | tr -d ' ')
(( sz0 > sz9 )) && _pass "level 0 (store) is larger than level 9 on compressible data" \
                   || _fail "level 0 (store) is larger than level 9 on compressible data" "store=$sz0 ultra=$sz9"

finish
