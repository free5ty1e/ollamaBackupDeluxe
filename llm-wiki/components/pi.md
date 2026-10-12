# components/pi

Purpose: how the Pi coding agent is installed here and what a faithful backup of it must contain.

(as of 2026-10-12, Pi 1.1.0)

## Managed install layout

| Item | Path | Notes |
|---|---|---|
| Agent home | `~/.pi` | 165 MB |
| Launcher | `~/.pi/agent/bin/pi` | a POSIX sh script; resolves the managed release at runtime |
| Version pin | `~/.pi/agent/install/current-version` | launcher reads this file (e.g. `1.1.0`) |
| Releases | `~/.pi/agent/install/releases/<ver>/node_modules/...` | the actual code; 158 MB |
| Staging | `~/.pi/agent/install/staging/` | partial downloads → **excluded** from backups |
| Settings | `~/.pi/agent/{settings.json, models.json, models-store.json}` | |
| Auth | `~/.pi/agent/auth.json` | **API keys — treat kit as secret** |
| Data | `~/.pi/agent/{sessions/, npm/}` | small, included |
| PATH symlink | `~/.local/bin/pi` → `../../.pi/agent/bin/pi` | relative link; restore recreates it exactly |

## Launcher resolution chain (why the whole `~/.pi` tree matters)

`pi` → `~/.local/bin/pi` (symlink) → `~/.pi/agent/bin/pi` (script) → reads
`install/current-version` → executes `install/releases/<ver>/node_modules/.bin/pi` → needs
`node` on PATH ([[components/node-runtime]]). Missing any link in this chain breaks `pi`, so the
restore recreates the symlink and verifies `pi --version` matches the manifest.

## Sensitive content

`auth.json` holds provider credentials. Kits also include Ollama's `id_ed25519`. Consequence:
store kits on encrypted media (FileVault volume or encrypted disk image). The web app and
scripts run as the local user only — same trust boundary as a terminal.

Cross-reference: [[components/ollama]], [[architecture/backup-archive-layout]], [[reference/paths]].
