# architecture/backup-archive-layout

Purpose: the exact contents of a backup kit `.7z` — the contract between backup.sh and restore.sh.

Top-level entries (only those that exist are added):

```
MANIFEST.txt                human-readable summary (versions, host, arch, model list, sizes, options)
manifest.env                machine-readable KEY=VALUE, source-able by bash (the restore contract)
Applications/Ollama.app     full app bundle (dereferenced real files)
home/.ollama/               per-entry links: config.json, id_ed25519*, models/, logs/, onboarding marker
                            (cache/ never; logs/ per --no-logs; models/ per --exclude-models)
home/.pi/agent/             per-entry: bin/, install/{current-version,managed-install.json,releases/},
                            auth.json, models*.json, settings.json, sessions/, npm/
                            (install/staging never)
app-support/Ollama/         ~/Library/Application Support/Ollama (db.sqlite etc.)
brew/Cellar/<formula>/      node + its dep chain (brew mode only)
brew/bin-entries.txt        "<name>\t<relative-target>" for each brew bin symlink captured
node-dist/*.tar.xz          official Node fallback runtime (if cached and not --no-node-dist)
restore-kit/                7zz binary + restore.sh + common.sh + verify.sh + RESTORE-README.md
project/                    copy of scripts/, webapp/, llm-wiki/, docs/, README, AGENTS.md, LICENSE
```

## manifest.env keys (source-able; values quoted)

Identity: `OBD_VERSION, CREATED_UTC, HOSTNAME, ARCH, MACOS_VERSION`
Ollama: `OLLAMA_APP_PATH, OLLAMA_HOME_PATH, OLLAMA_APP_SUPPORT_PATH, OLLAMA_VERSION`
Pi: `PI_HOME_PATH, PI_LAUNCHER_PATH, PI_VERSION`
Node: `NODE_MODE (brew|system|none), NODE_VERSION, NODE_REAL, NODE_FORMULAE (space list), BREW_PREFIX,
OPT_<SANITIZED_FORMULA>="../Cellar/<f>/<ver>" (one per formula)`
Content: `MODELS_COUNT, INCLUDE_LOGS, INCLUDE_NODE_DIST, EXCLUDE_MODELS, COMPRESS_LEVEL,
SIZE_TOTAL_KB, SIZE_MODELS_KB`

## Destination contract (restore side)

- Real restore: each entry maps back to its manifest-recorded original path (`OLLAMA_HOME_PATH` etc.).
- Sandbox (`OBD_DEST_PREFIX` set): every absolute destination becomes `<prefix><original-absolute-path>`
  — e.g. `/Applications/Ollama.app` → `$PREFIX/Applications/Ollama.app`. This single rule makes
  the full cycle testable without touching the host ([[reference/paths]]).

Sidecars written next to the archive: `<name>.7z.sha256`, `<name>.manifest.txt` (copy of MANIFEST.txt).

Related: [[architecture/backup-flow]], [[architecture/restore-flow]], [[components/node-runtime]].
