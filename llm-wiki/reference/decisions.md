# reference/decisions

Purpose: the decision record — what was chosen, why, and what was rejected.

## D1 — Compression default `-mx=5` (not 9)
GGUF weights are high-entropy binary; ultra level costs hours for ~1–2 % on 60 GB. User approved
the recommended level 2026-10-12. Levels remain selectable (0–9). Rejected: zstd tarballs (user
asked for .7z; 7zz also gives us self-extraction plumbing and solid archives).

## D2 — Symlink staging + 7zz's default dereference
Copying 61 GB into a staging dir doubles I/O. Staging = symlinks; default `7zz a` dereferences
them into clean staging-relative archive paths. NOTE: the `-l` switch does not exist in the 26.04
macOS build — do not add it back. Verified by tests/unit/test-7zip.sh.

## D3 — Self-contained kits
Each kit embeds `restore-kit/` (universal 7zz + restore/common/verify scripts + README) and a
full project copy. A kit + macOS = restore. No Homebrew, npm, network, or this repo required.

## D4 — Node: brew Cellar chain + official dist fallback
A bare node binary is useless (dylib chain — see [[components/node-runtime]]). Primary: faithful
Cellar + opt/bin symlink reconstruction from the manifest. Insurance: official node dist tarball
inside the kit, installable to `/usr/local/lib/obd-node-v<ver>`.

## D5 — Release bundle self-bootstrap
The web app must run on a fresh Mac with no Node: bundle ships official Node `.tar.xz` for both
arches; `start-webapp.sh` extracts to `.runtime/` on first launch (bsdtar is built into macOS).
Also ships one **universal** `bin/7zz` (the mac release asset is arch-agnostic — discovered live).

## D6 — Rename-aside restore semantics
Existing installs are moved to `*.pre-restore-<ts>`; nothing is deleted without explicit
`--purge-existing`. Rationale: restore touches irreplaceable data (models, keys); an accident
must be recoverable.

## D7 — Elevation via osascript GUI prompt
`/usr/local/bin` is root-owned; scripts try directly, then `osascript … with administrator
privileges` (works from the web-app context, one password prompt), then fail with manual
instructions. No pre-baked sudoers.

## D8 — Model enumeration from the manifests tree
`ollama list` requires a running server; backups must not depend on that. Walk
`models/manifests/<registry>/<ns>/<name>/<tag>` + `models/manifests-v2/…`.

## D9 — `ditto` for all data copies
Preserves xattrs, code signatures, resource forks — required for the signed Ollama app.

## D10 — Zero-dependency web app
Built-in `node:http` only; server-backed file explorer instead of browser FS APIs (Safari has no
`showDirectoryPicker`). The restore machine may have nothing installed — there must be nothing to
install. Tests use node:test (also built-in).

## D11 — OBD_* env override contract
Every path is overridable; restore accepts `OBD_DEST_PREFIX`. This converts "backup tool for one
machine" into a testable product (106 automated checks run against fixtures, CI on GitHub
macOS runners). See [[reference/paths]].

## D12 — Exclude ephemera
`~/.ollama/cache`, `~/.pi/agent/install/staging`, pid files: regenerable, and staging can hold
multi-MB partial downloads. Logs optional (default included — small and useful post-restore).
