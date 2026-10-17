#!/usr/bin/env bash
# bootstrap.sh — one-command setup for the GitHub Pages hosted UI.
# Deployed to Pages with PAGES_ORIGIN / REPO_URL baked in at build time.
# Downloads the latest release, installs it to ~/.ollama-backup-deluxe, and
# starts the engine pre-authorized for the Pages origin — so the hosted UI
# connects automatically and offers full backup/restore from the browser.
#
# Direct use (un-baked template): OBD_PAGES_ORIGIN=... OBD_REPO_URL=... ./bootstrap.sh
set -euo pipefail

PAGES_ORIGIN="${OBD_PAGES_ORIGIN:-__PAGES_ORIGIN__}"
REPO_URL="${OBD_REPO_URL:-__REPO_URL__}"

if [[ "$PAGES_ORIGIN" == "__PAGES_ORIGIN__" || "$REPO_URL" == "__REPO_URL__" ]]; then
  echo "This bootstrap template is not baked for a Pages deployment." >&2
  echo "Run with OBD_PAGES_ORIGIN and OBD_REPO_URL set." >&2
  exit 1
fi

[[ "$(uname -s)" == "Darwin" ]] || { echo "This installer is for macOS." >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo "unzip is required." >&2; exit 1; }

echo "Ollama Backup Deluxe — fetching the latest release…"
asset_url="$(curl -fsSL "https://api.github.com/repos/${REPO_URL#https://github.com/}/releases/latest" |
  python3 -c 'import json,sys
for a in json.load(sys.stdin).get("assets", []):
    if a["name"].endswith("-macos.zip"):
        print(a["browser_download_url"]); break' 2>/dev/null || true)"
if [[ -z "$asset_url" ]]; then
  # fallback: scrape the latest tag from the releases redirect
  tag="$(curl -fsSL -o /dev/null -w '%{url_effective}' "$REPO_URL/releases/latest" | sed -E 's|.*/tag/||')"
  [[ -n "$tag" ]] || { echo "Could not determine the latest release." >&2; exit 1; }
  asset_url="$REPO_URL/releases/download/$tag/ollama-backup-deluxe-${tag#v}-macos.zip"
fi
echo "Release: $asset_url"

ZIP="$(mktemp -d)/release.zip"
curl -fL --retry 3 -o "$ZIP" "$asset_url"

DEST="$HOME/.ollama-backup-deluxe"
STAGE="$(mktemp -d)"
unzip -qo "$ZIP" -d "$STAGE"
INNER="$(find "$STAGE" -maxdepth 1 -type d -name 'ollama-backup-deluxe-*' | head -1)"
[[ -n "$INNER" ]] || { echo "Unexpected archive layout." >&2; exit 1; }
mkdir -p "$DEST"
rm -rf "$DEST.next"; mv "$INNER" "$DEST.next" && rm -rf "$DEST" && mv "$DEST.next" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
rm -rf "$STAGE"

echo "Starting the engine (authorized for $PAGES_ORIGIN)…"
( cd "$DEST" && OBD_ALLOWED_ORIGIN="$PAGES_ORIGIN" nohup ./start-webapp.sh > "$DEST/engine.log" 2>&1 & )

echo
echo "✅ Done. Two ways in:"
echo "   • Reload the GitHub Pages tab — it auto-connects within ~10 seconds."
echo "   • Or open http://127.0.0.1:8686 directly (the local copy of the UI)."
echo "   Engine log: $DEST/engine.log — stop with: pkill -f 'webapp/server.js'"
