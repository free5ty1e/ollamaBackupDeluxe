# AGENTS.md — Ollama Backup Deluxe

## Repository rules (binding for every session)

### Git workflow — STRICT
- **NEVER perform any git write operation other than `git add` (staging).**
- Forbidden without exception flow: `git commit`, `git push`, `git tag`, `git branch` writes,
  `git checkout -- <file>`/`git restore` (destructive), `git reset`, `git rebase`, `git merge`.
- **The user commits — always.** After finishing a cycle of changes:
  1. `git add -A` (or targeted `git add <paths>` when appropriate),
  2. suggest a commit message (conventional, imperative, ≤ 72 chars subject + body bullets),
  3. present the changes for review. The user runs the commit.
- If the user explicitly asks for a special git write action (e.g. "commit this for me"),
  **confirm at least twice** with the user before executing, then perform only that exact action.

### Documentation freshness — before presenting changes
- After EVERY work cycle, before messaging the user with results:
  update `README.md` if user-facing behavior changed, and ingest into `llm-wiki/` per
  `llm-wiki/SCHEMA.md` (topic pages + `index.md` + append to `log.md`).
- Update `docs/plans/` checklists when plan milestones complete.

### Safety invariants (code-level, also binding)
- Restore never deletes: renames existing targets aside. `OBD_*` env overrides for every path.
- Web app stays zero-npm-dependency. Scripts log via common.sh helpers.

## Project

Tools (CLI scripts + zero-dependency web app) to create **fully offline-restorable** backups of
the local LLM inference stack on macOS: Ollama (app, CLI, models, data), the Pi coding agent
(managed install, config, sessions), and the Node.js runtime Pi depends on. Backups are `.7z`
"backup kits" that are self-contained: they carry their own extractor, restore scripts, and the
project itself, so a fresh Mac can be restored with no internet.

## Layout

- `scripts/` — `common.sh` (shared lib), `prerequisites.sh`, `backup.sh`, `restore.sh`, `verify.sh`
- `webapp/` — zero-dependency Node HTTP server (`server.js`, port 8686) + `public/` UI
- `docs/plans/` — implementation plans (start with the dated plan doc)
- `llm-wiki/` — persistent LLM-maintained knowledge base (see `llm-wiki/SCHEMA.md`)
- `bin/`, `logs/` — local, gitignored (7zz binary, cached node tarball, job logs)

## Conventions

- All path defaults are overridable via `OBD_*` env vars (see `scripts/common.sh`) — this is what
  makes sandboxed end-to-end tests possible; never hard-code a path in a script.
- Scripts: `set -euo pipefail`, log via `obd_info/obd_ok/obd_warn/obd_error/obd_die` from common.sh.
- Restore must never delete: rename existing targets to `*.pre-restore-<ts>`.
- Compression default `-mx=5` (GGUF model blobs are incompressible; higher wastes hours).
- Web app must stay zero-npm-dependency (built-in `node:http` only) — offline constraint.

## llm-wiki maintenance (the schema lives at llm-wiki/SCHEMA.md)

This project follows the "LLM wiki" pattern (source of truth: `llm-wiki/sources/llm-wiki-pattern.md`).
The agent maintains the wiki; the human sources/asks. Operations:

- **Ingest** — after adding/changing plans, docs, scripts, or after a backup/restore run, read the
  source, then update: the relevant component/architecture/runbook pages, `index.md` (one line per
  page), and append a parseable entry to `llm-wiki/log.md` (`## [YYYY-MM-DD] ingest|query|lint|build | title`).
- **Query** — answer from the wiki (read `index.md` first); file valuable answers back as pages.
- **Lint** — periodically check for stale claims, orphans, missing cross-links, contradictions.

Key pages to keep current after any code change:
`architecture/backup-flow.md`, `architecture/restore-flow.md`, `architecture/backup-archive-layout.md`,
`reference/paths.md`, `reference/decisions.md`.
