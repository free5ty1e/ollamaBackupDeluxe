# reference/paths

Purpose: every path this tool touches, with defaults and the `OBD_*` override contract.

## Real-machine defaults (as of 2026-10-12)

| Component | Path |
|---|---|
| Ollama app | `/Applications/Ollama.app` |
| Ollama CLI symlink | `/usr/local/bin/ollama` |
| Ollama data | `~/.ollama` |
| Ollama app data | `~/Library/Application Support/Ollama` |
| Pi home | `~/.pi` |
| Pi launcher | `~/.local/bin/pi` |
| Brew prefix | `/opt/homebrew` (arm64) / `/usr/local` (x86_64) |
| Project-local | `<repo>/bin` (7zz), `<repo>/cache/node-dist/`, `<repo>/logs/`, `<repo>/dist/` |

## OBD_* override contract (the testability layer)

Defined in `scripts/common.sh`; every script honors them, none hard-codes a path:

| Variable | Default |
|---|---|
| `OBD_HOME` | `$HOME` |
| `OBD_OLLAMA_APP` | `/Applications/Ollama.app` |
| `OBD_OLLAMA_CLI` | `/usr/local/bin/ollama` |
| `OBD_OLLAMA_HOME` | `$OBD_HOME/.ollama` |
| `OBD_OLLAMA_APP_SUPPORT` | `$OBD_HOME/Library/Application Support/Ollama` |
| `OBD_PI_HOME` | `$OBD_HOME/.pi` |
| `OBD_PI_LAUNCHER` | `$OBD_HOME/.local/bin/pi` |
| `OBD_BREW_PREFIX` | arch-dependent (table above) |
| `OBD_PROJECT_DIR` | auto (script dir/..) |
| `OBD_7ZZ` / `OBD_KIT_7ZZ` | 7zz resolution inputs (env → kit → `bin/` → PATH) |
| `OBD_NO_QUIT` | `1` = never stop/restart Ollama (used by tests) |
| `OBD_PORT` | web app port (8686) |

Restore-only:

| Variable | Meaning |
|---|---|
| `OBD_DEST_PREFIX` | sandbox: every absolute destination becomes `<prefix><original-absolute-path>` |

## Fixture mirror (tests/lib/sandbox.sh)

`make_fixture_tree <root>` builds a miniature replica: fake `Ollama.app` (script "binary"
answering `--version`), `~/.ollama` with 3 manifest entries incl. manifests-v2, fake `~/.pi`
managed install (with a staging dir that must be excluded), fake brew Cellar (`node` 9.9.9 +
`icu4c@9`), a **brew stub on PATH** (so `brew deps node` returns the fixture's dep regardless of
the host's real brew), and Application Support. Suites point `OBD_*` at it and restore with
`OBD_DEST_PREFIX` — nothing outside `/tmp` + `tests/.tmp` is ever touched.

Related: [[architecture/backup-archive-layout]], [[components/pi]], [[components/node-runtime]].
