# components/opencode

Purpose: how OpenCode (the open-source coding agent) is installed here and what a faithful
backup captures.

(as of 2026-10-12, OpenCode 1.19.0, official install script; data layout observed after first run)

## Install shape (curl installer)

| Item | Path | Notes |
|---|---|---|
| Binary | `~/.opencode/bin/opencode` | self-contained Mach-O arm64 (138 MB, bundles its runtime — no Node needed) |
| Plugin runtime | `~/.opencode/{package.json, package-lock.json, node_modules/}` | `@opencode-ai/plugin` (61 MB) — **included**: reinstalling it offline would need npm |
| PATH wiring | `~/.zshrc`: `export PATH=/Users/chris/.opencode/bin:$PATH` (added by the installer) | why shell rc capture exists — see below |

## Data created on first run (all captured now)

| Item | Path | Notes |
|---|---|---|
| Config | `~/.config/opencode/` | `opencode.jsonc` (user config) + `package.json` + plugin `node_modules/` (61 MB, needed offline) + `.gitignore` |
| Sessions | `~/.local/share/opencode/` | `opencode.db{,-wal,-shm}` (SQLite session store), `snapshot/`, `repos/`, `log/` |
| State | `~/.local/state/opencode/` | `model.json` (last model), `prompt-history.jsonl`, `locks/` (tiny) |
| Cache | `~/.cache/opencode/` | **excluded** (regenerable, per [[reference/decisions]] D12) |

## Backup/restore specifics

- Staging is **selective**: `~/.config` also holds other apps (cagent, filezilla) — only
  `~/.config/opencode` is staged, as `home/.config/opencode`. Same slice approach for
  `~/.local/share/opencode` (sibling of the Claude entry under the same real staging dir) and
  `~/.local/state/opencode`.
- No launcher symlink to recreate — PATH wiring travels in the shell rc files
  ([[architecture/restore-flow]] §3d).
- `opencode.db` is SQLite with -wal/-shm sidebars: quit OpenCode before a backup for a
  consistent db (same reasoning as the Ollama db, [[architecture/backup-flow]]).
- Version detection: `~/.opencode/bin/opencode --version` → first token (`1.19.0`).

## Open items

- [ ] Watch `~/.config/opencode/opencode.jsonc` for local-model provider config (it's what makes
      OpenCode usable offline — captured).

Cross-reference: [[components/claude]], [[components/pi]], [[reference/paths]],
[[runbooks/offline-restore]].
