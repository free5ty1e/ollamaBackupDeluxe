# components/claude

Purpose: how Claude Code (Anthropic's CLI) is installed here and what a faithful backup captures.

(as of 2026-10-12, Claude Code 2.1.251, native installer)

## Install shape (native installer, NOT npm)

| Item | Path | Notes |
|---|---|---|
| Versioned runtime | `~/.local/share/claude/versions/<ver>` | single self-contained Mach-O arm64 binaries (bun-compiled, **no Node needed**); 188 MB total |
| Launcher symlink | `~/.local/bin/claude` → **absolute** `/Users/chris/.local/share/claude/versions/2.1.251` | absolute target — restore must remap it through the destination mapping (see below) |
| Data | `~/.claude/` | `settings.json`, `sessions/`, `backups/`, `cache/`, `downloads/` (584 KB — captured whole; too small to bother excluding regenerable subdirs) |
| PATH | `~/.local/bin` already on PATH via `~/.zshrc` | shared with the Pi launcher |

## Backup/restore specifics

- Backup records `CLAUDE_LAUNCHER_TARGET` (the raw symlink text) in `manifest.env`.
- Restore recreates the launcher and, because the recorded target is absolute, **rewrites** any
  prefix matching `CLAUDE_SHARE_PATH` to the mapped destination — a no-op in real restores and
  what keeps `OBD_DEST_PREFIX` sandbox tests coherent ([[reference/paths]]).
- Version detection: launcher `--version` → first token (`2.1.251`); falls back to the newest
  entry in `versions/` (sort -V) when the launcher is absent.

## Local-model relevance

Claude Code can be pointed at local providers (e.g. an Ollama-compatible endpoint) via settings —
another reason the restored `~/.claude/settings.json` matters offline.

Cross-reference: [[components/pi]], [[components/opencode]], [[components/node-runtime]],
[[architecture/restore-flow]], [[reference/decisions]].
