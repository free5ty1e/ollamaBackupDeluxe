# introduction.md — START HERE (initial prompt for any agent or developer)

> **How to use this document:** if you are an agent joining this repository, treat this file as
> your briefing. Read it top to bottom, then follow "Your first five actions" before doing
> anything else. If you are a human developer, it is the fastest orientation we have.

## What this project is

**Ollama Backup Deluxe** (`obd`) is a macOS tool — bash scripts plus a zero-dependency web app —
that produces **fully offline-restorable backups of the local LLM inference stack**:

- **Ollama** (app bundle, CLI, all model weights, identity keys, app database)
- The AI coding harnesses: **Pi**, **Claude Code**, **OpenCode** (installs, configs, auth, sessions)
- The **Node.js runtime** (full Homebrew Cellar chain + official dist fallback — Pi needs it)
- **Shell rc files** (PATH wiring) and the tool's own restore kit

Backups are self-contained `.7z` "backup kits": they carry their own extractor, restore scripts,
and a copy of this project, so a fresh Mac can be restored **with zero internet**. A secondary
**devcontainer kit** (`<name>-devcontainer.tar.gz`) gives Linux containers the ollama CLI +
harnesses (no models) wired to the host's Ollama over the network (`ollama launch pi`).

## Purpose (the problem it solves)

The failure scenario: internet is unavailable (outage, travel, day-one new machine), a Mac must
be rebuilt, and `ollama pull`, `brew install`, app downloads and harness installers are all
unreachable. Every byte needed to run local inference and the user's coding harnesses must be
captured while online; restore must require nothing but the kit and macOS itself. Design
principle: **restore is always possible offline, and restore never deletes** (existing installs
are renamed to `*.pre-restore-<ts>`).

## How it is used

1. **On the source Mac (online):** `./scripts/prerequisites.sh` once → `./start-webapp.sh` →
   BACKUP (or `scripts/backup.sh --dest <dir>`). Produces the `.7z` kit + sidecars.
2. **On a fresh Mac (offline):** download a release bundle from GitHub Releases (or build one by
   pushing a `v*` tag), unzip, `./start-webapp.sh` (self-boots bundled Node + 7zz) → RESTORE →
   pick the kit. Or pure Terminal via the kit's embedded `restore-kit/restore.sh`.
3. **In a Linux devcontainer:** restore the devcontainer kit → the container talks to the Mac's
   Ollama over the network (`OLLAMA_HOST`), no models installed there.
4. **Verification anytime:** `scripts/verify.sh` audits the live stack (17/17 on the source Mac).

## Repository structure

| Path | What it is |
|---|---|
| `scripts/` | `common.sh` (shared lib + `OBD_*` override contract), `prerequisites.sh`, `backup.sh`, `restore.sh`, `verify.sh`, `capture-devcontainer.sh`, `restore-devcontainer.sh`, `build-release.sh` |
| `webapp/` | zero-dependency Node HTTP server (`server.js`, port 8686) + `public/` UI (three hosting modes: local / Pages-remote / guide) |
| `tests/` | bash harness (`run-tests.sh`, lib/assert.sh, lib/sandbox.sh fixture trees) + `webapp/` node:test suite |
| `docs/plans/` | dated implementation plans (start: `2026-10-12-initial-implementation-plan.md`) |
| `llm-wiki/` | the knowledge base you are responsible for maintaining (schema: `SCHEMA.md`) |
| `devcontainer/` | example validation container for devcontainer-kit restores |
| `.github/workflows/` | `ci.yml` (every PR/push), `release.yml` (tag `v*` → release bundle), `pages.yml` (Pages site) |
| `bin/`, `cache/`, `logs/`, `dist/` | local only, gitignored (7zz, payload caches, job logs, release builds) |

## Where to find more details

- **`AGENTS.md` (repo root) — BINDING RULES. Read it first.** Git workflow (you may only `git add`;
  the human commits), documentation freshness duties, safety invariants.
- **`docs/plans/2026-10-12-initial-implementation-plan.md`** — the full design: system inventory,
  architecture, ADRs, CI/CD, release bundle layout, test strategy (§4b, §9, §10).
- **`README.md`** — user-facing documentation (quick starts, offline restore, Pages modes).
- **`llm-wiki/index.md`** — catalog of every knowledge page (components, architecture, runbooks,
  reference). The wiki is your persistent memory for this project: ingest after every cycle,
  file valuable answers back, lint for staleness.
- **`llm-wiki/reference/troubleshooting.md`** — failure modes already hit and fixed (don't rediscover them).

## Current state (as of 2026-10-12)

- Implemented and sandbox-tested end to end: **181 automated checks green**, ShellCheck clean.
- Real-machine audit passes 17/17 (Ollama 0.40.3, 7 models, Pi 1.1.0, Claude 2.1.251, OpenCode 1.19.0).
- Not yet done: the user's real 61 GB backup run, a first tagged release (`v*` → release CI), and
  a real restore drill on target hardware.

## Your first five actions

1. Read `AGENTS.md` — the git and documentation rules there are non-negotiable.
2. Run `tests/run-tests.sh` — confirm the suite is green before touching anything.
3. Run `scripts/verify.sh --expect-server` — see the real machine state this tool manages.
4. Read `docs/plans/2026-10-12-initial-implementation-plan.md` (skim §3–§6, §9–§10) and
   `llm-wiki/reference/decisions.md` — most questions about "why is it built this way" are
   answered there; don't redesign without reading them.
5. Read `llm-wiki/SCHEMA.md` — after every work cycle you must ingest your changes into the wiki
   (pages + `index.md` + `log.md`) **before** presenting results, stage everything with
   `git add`, and suggest a commit message. You never commit.

## Conventions that will save you time

- Every path is overridable via `OBD_*` env vars; `OBD_DEST_PREFIX` sandboxes restores. Fixtures
  live in `tests/lib/sandbox.sh`. Never hard-code a path, never test against the real install.
- `set -euo pipefail` traps: `cmd | head`, `grep -q` under pipes (SIGPIPE), `[[ ]] && cmd` as a
  loop's last statement, `((x++))` — see `llm-wiki/reference/troubleshooting.md` first.
- Compression default `-mx=5` (GGUF is incompressible; level 9 wastes hours).
- The web app stays zero-npm-dependency, binds localhost only, and its Pages copy is static.
