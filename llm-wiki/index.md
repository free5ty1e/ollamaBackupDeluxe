# llm-wiki index

Catalog of the wiki. One line per page. The LLM updates this on every ingest; read it first
when answering queries. (Pattern source: [[sources/llm-wiki-pattern]].)

## Meta

- [[SCHEMA]] — operating manual for maintaining this wiki.
- [[log]] — chronological, grep-parseable record of ingests/builds/restores/lints.

## Overviews

- [[overview]] — what Ollama Backup Deluxe is, the offline-restore thesis, current state.

## Components (the machines and software being backed up)

- [[components/ollama]] — Ollama app/CLI/data layout on this Mac; 61 GB models; manifest trees.
- [[components/pi]] — Pi's managed install, launcher resolution chain, config/auth files.
- [[components/claude]] — Claude Code native install (versioned self-contained binaries, absolute launcher symlink).
- [[components/opencode]] — OpenCode binary + post-first-run data: config (node_modules), session db, state; cache excluded.
- [[components/node-runtime]] — Homebrew node + ~25 dylib formulae; why bare-binary backups fail.
- [[components/seven-zip]] — 7zz acquisition paths, switch behavior, bash pipefail traps.

## Architecture (this tool)

- [[architecture/backup-archive-layout]] — exact .7z contents: staging names → restore destinations.
- [[architecture/backup-flow]] — preflight → symlink staging → 7zz → sidecars; options; guards.
- [[architecture/restore-flow]] — quit → extract → rename-aside → reinstall → symlinks → verify.
- [[architecture/webapp]] — zero-dependency server, endpoints, job runner, file explorer; Pages hosting modes (local/remote/guide).
- [[architecture/devcontainer-kit]] — secondary restore: Linux toolset kit (ollama CLI + harnesses, no models), captured online, restored offline.

## Runbooks (do-this-when procedures)

- [[runbooks/offline-restore]] — restoring with wifi off: what you need, exact steps, fallbacks.
- [[runbooks/fresh-os-reload]] — new MacBook end-to-end incl. release bundle self-bootstrap.
- [[runbooks/devcontainer-restore]] — Linux devcontainer: toolset only, OLLAMA_HOST to this Mac.

## Reference

- [[reference/paths]] — canonical path table + OBD_* env override contract (testability).
- [[reference/decisions]] — ADR log: compression level, symlink staging, self-contained kits…
- [[reference/troubleshooting]] — known failure modes (set -e traps, TCC, SIGPIPE) and fixes.

## Sources (immutable raw material)

- [[sources/llm-wiki-pattern]] — karpathy's LLM-wiki gist (verbatim copy, 2026-10-12).
