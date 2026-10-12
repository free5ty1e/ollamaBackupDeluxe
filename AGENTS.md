# AGENTS.md — Ollama Backup Deluxe

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
