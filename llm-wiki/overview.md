# overview

Ollama Backup Deluxe is a macOS tool (bash scripts + a zero-dependency local web app) that
produces **fully offline-restorable** backups of the local LLM inference stack — Ollama
(app/CLI/models/db), the Pi coding agent (managed install/config/sessions), and the Node.js
runtime Pi needs — packaged as self-contained `.7z` "backup kits" that carry their own extractor
and restore scripts.

**Thesis.** The failure scenario this tool exists for: the internet is unavailable (outage,
travel, new-machine day one), a Mac needs rebuilding, and `ollama pull`, `brew install`, app
downloads, and Pi's installer are all unreachable. Therefore every byte needed to run local
inference must be captured while online, and restore must require nothing but the archive and
macOS itself (bash + built-in tools for the CLI path; the bundled Node runtime for the web UI).

**Current state (as of 2026-10-12):** implemented and sandbox-tested end to end (106 automated
checks green); the 61 GB real-world kit has not yet been run by the user — that's the next
milestone, followed by a real restore drill on target hardware.

**Structure of the solution:**
- Backup = preflight checks → symlink staging (no 61 GB duplication) → `7zz a` (level 5 default)
  → sidecars (`.sha256`, `.manifest.txt`). The archive embeds restore-kit (7zz + scripts) and a
  project copy. See [[architecture/backup-archive-layout]].
- Restore = quit Ollama → extract → rename-aside existing installs → `ditto` copies → symlink
  recreation (CLI, Pi launcher, brew opt/bin) → optional node-dist fallback → health check →
  verify against manifest. See [[architecture/restore-flow]].
- The web app ([[architecture/webapp]]) wraps both with a server-backed file explorer and live
  job logs; it self-bootstraps its Node runtime from the release bundle ([[runbooks/fresh-os-reload]]).

**Non-goals:** backing up Homebrew itself or unrelated formulae; Windows/Linux targets;
scheduled backups (a cron wrapper could be added later); model quantization/retention policies.

Cross-reference: design rationale in [[reference/decisions]]; the implementation plan lives at
`docs/plans/2026-10-12-initial-implementation-plan.md` (the wiki summarizes; the plan is source).
