# components/node-runtime

Purpose: why Node is the hardest component to restore offline, and the two-layer strategy.

(as of 2026-10-12, Node v26.11.1 via Homebrew, arm64)

## The trap

`node` is not self-contained here:

- `/opt/homebrew/bin/node` → `../Cellar/node/26.11.1/bin/node`
- The binary dylib-links **~25 Homebrew formulae**: abseil, ada-url, brotli, c-ares,
  ca-certificates, fmt, hdrhistogram_c, highway, `icu4c@78`, libffi, libnghttp2, libuv, llhttp,
  lz4, merve, nbytes, `openssl@4`, readline, simdjson, simdutf, sqlite, uvwasi, xz, zstd
  (runtime chain enumerated live via `brew deps node`).

→ Backing up the bare binary produces a node that can't start on a machine missing those dylibs.

## The two-layer strategy

1. **Faithful restore (primary):** capture `Cellar/<formula>` for node + its whole dep chain,
   plus the `opt/<formula>` relative symlink targets and the `bin/` symlinks whose resolved
   targets land inside those Cellars (node, npm, npx, corepack, …). Restore copies the Cellars
   back under the same prefix and recreates the symlinks from `manifest.env` (`OPT_*` keys) and
   `brew/bin-entries.txt`. Because paths are identical (`/opt/homebrew/...`), everything just works.
2. **Fallback runtime (insurance):** the official nodejs.org dist tarball (`node-v<ver>-darwin-<arch>.tar.xz`,
   ~29 MB) is cached at backup time (`cache/node-dist/`) and shipped inside the kit (`node-dist/`).
   If the brew chain can't be restored, restore installs it to `/usr/local/lib/obd-node-v<ver>`
   and symlinks `/usr/local/bin/node` (one elevated step). Also used by the **release bundle** to
   self-bootstrap the web app on a fresh Mac — see [[runbooks/fresh-os-reload]].

## Detection

`obd_detect_node` (scripts/common.sh) classifies: `brew` (real path under the brew prefix's
Cellar) / `system` / `none`, and records version + real path + formula chain into the manifest.

Cross-reference: [[components/pi]], [[architecture/backup-archive-layout]], [[reference/decisions]].
