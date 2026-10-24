# architecture/devcontainer-kit

Purpose: the SECONDARY restore path — a Linux devcontainer that uses the Mac host's Ollama
server over the network. Excludes models/data; includes the ollama CLI toolset and the
harnesses so `ollama launch pi` / `ollama launch claude` work in the container.

## Why a separate artifact

The main kit is a `.7z` — opening it requires 7-Zip, which a fresh container doesn't have
(chicken-and-egg). The devcontainer kit is therefore a **plain `tar.gz`** (`<name>-devcontainer.tar.gz`,
written next to the `.7z`): every Linux has `tar`. It carries its own Linux `7zz` for reading the
main kit (harness configs + the Pi tree live in the `.7z`).

## Contents of `obd-devcontainer/` (inside the tar.gz)

| Item | Purpose |
|---|---|
| `restore-devcontainer.sh`, `common.sh` | the Linux restore script |
| `ollama-linux-{amd64,arm64}` | ollama CLI only (extracted from the official `ollama-linux-<arch>.tar.zst`, version-pinned to the installed ollama) — a client; inference stays on the host |
| `node-v<ver>-linux-{x64,arm64}.tar.xz` | official Node dists — runs the Pi harness |
| `claude-linux-{arm64,x64}` | Claude Code Linux builds, sha256-verified against `downloads.claude.ai/claude-code-releases/<ver>/manifest.json` |
| `opencode-linux-{arm64,x64}` | OpenCode Linux builds |
| `7zz-linux-{arm64,x64}` | 7-Zip for Linux (kit self-extraction) |
| `README-DEVCONTAINER.md` | instructions |

## Capture (host side, online — `scripts/capture-devcontainer.sh`)

- All payloads cached in `cache/devcontainer/` — the first backup downloads (~3 GB for the two
  ollama tarballs, most of which is discarded after extracting `bin/ollama`), later backups reuse.
- Every step is best-effort; failures skip that payload with a clear warning and the backup
  still succeeds. `--no-devcontainer` / `OBD_SKIP_DC` opt out. `OBD_CACHE_DIR` relocates the cache.
- URL patterns (verified live 2026-10-12): ollama `ollama.com/download/ollama-linux-<arch>.tar.zst?version=<v>`
  (tgz fallback), claude `downloads.claude.ai/claude-code-releases/<ver>/linux-<arch>/claude`
  (manifest-indexed), opencode `github.com/anomalyco/opencode/releases/download/v<ver>/opencode-linux-<arch>.zip`,
  node `nodejs.org/dist/...`, 7-Zip GitHub releases.
- Constraint: **glibc** payloads — Debian/Ubuntu-style devcontainer images, not Alpine/musl.

## Restore (container side, offline — `scripts/restore-devcontainer.sh`)

1. Bundled `7zz-linux-<arch>` extracts the main `.7z` (harness configs + Pi tree come from it).
2. Installs: `ollama` + `claude` + `opencode` → `/usr/local/bin` (root/sudo, else `~/.local/bin`
   with a PATH note); Node dist → `/usr/local/lib/obd-node-v<ver>` + bin symlinks; Pi tree →
   `~/.pi` + launcher symlink; `~/.claude`, `~/.config/opencode`, `~/.local/share/opencode`,
   `~/.local/state/opencode` (rename-aside semantics). **No ollama models or data.**
3. Wires env: writes `~/.obd-devcontainer.sh` (`PATH` + `OLLAMA_HOST`, default
   `http://host.docker.internal:11434`, `--ollama-host` to override) and appends an idempotent
   source line to `.bashrc`/`.zshrc`.
4. Verifies each toolset binary (exec checks on Linux; placement checks when run on macOS for
   tests) and probes `$OLLAMA_HOST/api/version` — unreachable host is a **warning** (toolset
   install is complete; expose Ollama on the host and re-check).

## Host prerequisite

Ollama must listen beyond 127.0.0.1: Ollama app → "Expose Ollama to the network"
(equivalent to `OLLAMA_HOST=0.0.0.0`). Documented in the kit README and runbook.

## Validation

`devcontainer/` in this repo holds an example Debian container (Dockerfile + devcontainer.json +
README) to rehearse a restore before depending on it. Sandbox-tested end-to-end on macOS via
`OBD_DEST_PREFIX` with fake payloads (tests/unit/test-devcontainer.sh — 33 checks).

Related: [[architecture/restore-flow]], [[components/claude]], [[components/opencode]],
[[components/node-runtime]], [[runbooks/devcontainer-restore]], [[reference/decisions]].
