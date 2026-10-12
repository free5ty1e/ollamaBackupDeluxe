# components/ollama

Purpose: exactly what Ollama looks like on this Mac when installed from the website app
installer — every path the backup must capture, and the quirks.

(as of 2026-10-12, Ollama 0.40.3, macOS 15.6.1 arm64)

## Install shape (app installer, NOT brew)

| Item | Path | Notes |
|---|---|---|
| App bundle | `/Applications/Ollama.app` | 624 MB, code-signed; the CLI binary lives at `Contents/Resources/ollama` (plus all ggml dylibs) |
| CLI symlink | `/usr/local/bin/ollama` → `…/Ollama.app/Contents/Resources/ollama` | `/usr/local/bin` is root-owned → restore needs one elevated step |
| Data home | `~/.ollama` | **61 GB** total |
| ├ models | `~/.ollama/models/{blobs,manifests,manifests-v2,metadata}` | weights are content-addressed blobs |
| ├ identity | `~/.ollama/id_ed25519{,.pub}` | regenerable but captures it for consistency |
| ├ config | `~/.ollama/config.json` | |
| ├ onboarding | `~/.ollama/onboarding-v1.completed` | marker file |
| └ cache/logs | `~/.ollama/cache`, `~/.ollama/logs` | cache excluded from backup (regenerable); logs optional |
| App data | `~/Library/Application Support/Ollama` | `db.sqlite{,-shm,-wal}` — quit Ollama before capture for a consistent db |
| Autostart | none in `~/Library/LaunchAgents` | the app registers itself as a Login Item; must be re-enabled manually after restore |

## Model registry without a server

`ollama list` needs the server; backups can't rely on that. Model enumeration walks the
manifest trees instead (implemented as `obd_model_list` in `scripts/common.sh`):

- classic: `models/manifests/<registry>/<ns>/<name>/<tag>` (e.g. `registry.ollama.ai/library/gemma4/e4b` → `gemma4:e4b`)
- new: `models/manifests-v2/ollama.com/<ns>/<name>/<tag>` — same rendering, registry host stripped
- non-library namespaces render as `ns/name:tag`

This machine currently has 7 models. The exact list is baked into every kit's `manifest.env`
(`MODELS_COUNT`) and `MANIFEST.txt`, and restore diff-checks against it (see
[[architecture/restore-flow]]).

## Restore notes

- `ditto` (not `cp`) copies the bundle — preserves xattrs + code signature, so Gatekeeper stays happy.
- Replacing an existing signed bundle can trip macOS **App Management (TCC)** on Sequoia+; the
  restore script moves the old bundle aside first, and prints manual drag-to-Trash instructions if
  the rename is refused. On a fresh OS the target doesn't exist → plain copy, no TCC involved.
- Related: [[components/pi]], [[reference/paths]], [[runbooks/offline-restore]].
