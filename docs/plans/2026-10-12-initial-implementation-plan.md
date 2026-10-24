# Ollama Backup Deluxe — Initial Implementation Plan

**Date:** 2026-10-12
**Status:** Approved / in progress
**License:** GPLv3 (repo root `LICENSE`)
**Author:** Chris + Pi (coding agent)

---

## 1. Goal

One-command, **fully offline-restorable** backups of the local LLM inference stack on this Mac:

- **Ollama** (app bundle, CLI, models, keys, config, app database)
- **Pi** coding agent (managed install, settings, auth, sessions, launcher)
- **Node.js runtime** (Pi's hard dependency)
- The **project's own scripts + web app** (so the backup can restore itself)

Two primary functions, available both from a web UI and the CLI:

1. **BACKUP MY CURRENT LOCAL INFERENCE SETUP** → creates a max-portable `.7z` "backup kit"
2. **RESTORE A LOCAL INFERENCE SETUP** → reinstalls everything on a fresh macOS with **zero internet**

The restore path must work when the only things available are: the `.7z` file, a fresh macOS install, and an external drive. No Homebrew, no app installers, no app store, no network.

---

## 2. System inventory (inspected 2026-10-12)

Verified live on the target machine (macOS 15.6.1, Apple Silicon `arm64`):

### Ollama (installed from website `.dmg`/app installer)

| Item | Path | Size / notes |
|---|---|---|
| App bundle | `/Applications/Ollama.app` | 624 MB, code-signed |
| CLI symlink | `/usr/local/bin/ollama` → `…/Ollama.app/Contents/Resources/ollama` | root-owned dir, needs sudo to recreate |
| Data home | `~/.ollama` | **61 GB** total |
| ├ models | `~/.ollama/models/{blobs,manifests,manifests-v2,metadata}` | 61 GB (GGUF weights) |
| ├ config | `~/.ollama/config.json`, `id_ed25519{,.pub}`, `onboarding-v1.completed` | tiny |
| ├ logs | `~/.ollama/logs` | 88 KB |
| └ cache | `~/.ollama/cache` | regenerable → **exclude** |
| App data | `~/Library/Application Support/Ollama` | `db.sqlite{,-shm,-wal}`, `ollama.pid` |
| Autostart | none in `~/Library/LaunchAgents` | new app uses Login Items; user re-enables post-restore (documented) |

Model manifests live under both `manifests/registry.ollama.ai/...` (classic) and
`manifests-v2/ollama.com/...` (new). The model list is enumerable **without a running
server** by walking these trees (format: `library/gemma4/e4b` → `gemma4:e4b`).

### Pi coding agent (managed install)

| Item | Path | Size / notes |
|---|---|---|
| Agent home | `~/.pi` | 165 MB |
| ├ launcher | `~/.pi/agent/bin/pi` (sh script) | resolves managed release via `install/current-version` |
| ├ install | `~/.pi/agent/install` (releases/1.1.0, current-version, managed-install.json, staging) | 158 MB; `staging/` = partial downloads → **exclude** |
| ├ config | `auth.json`, `settings.json`, `models.json`, `models-store.json` | contains API keys → sensitive |
| └ data | `sessions/`, `npm/` | small, include |
| PATH symlink | `~/.local/bin/pi` → `../../.pi/agent/bin/pi` | recreated at restore |
| PATH source | `~/.zshrc`: `export PATH="$HOME/.local/bin:$PATH"` | preserved inside project copy; restore script recreates symlink |

### Node.js (Pi's runtime dependency) — the hard part

- `node` v26.11.1 from **Homebrew Cellar** (`/opt/homebrew/bin/node` → `Cellar/node/26.11.1/bin/node`), 77 MB
- The binary links **~25 Homebrew dylib formulae** (`abseil`, `ada-url`, `brotli`, `c-ares`,
  `ca-certificates`, `fmt`, `hdrhistogram_c`, `highway`, `icu4c@78`, `libffi`, `libnghttp2`,
  `libuv`, `llhttp`, `lz4`, `merve`, `nbytes`, `openssl@4`, `readline`, `simdjson`, `simdutf`,
  `sqlite`, `uvwasi`, `xz`, `zstd`) → a bare binary backup **will not work**
- `/opt/homebrew` is **user-writable** on this machine; `/usr/local/bin` needs sudo; `/Applications` is admin-writable
- Fallback: official nodejs.org dist tarball for `darwin-arm64` (~25 MB compressed) — self-contained

### Tooling

- `7zz`/`7z` **not installed**; `brew` present → prerequisites script installs `sevenzip` or
  downloads the official 7-Zip macOS binary into the project `bin/` (dequarantined)
- Web app must run on **zero npm dependencies** (built-in `node:http`) so nothing else is ever needed

---

## 3. Architecture

### 3.1 The "backup kit" (archive contents)

Single `.7z` archive, structured so restore is pure file-copy + symlink recreation:

```
<name>.7z
├── MANIFEST.txt            # human-readable summary (versions, sizes, model list, dates)
├── manifest.env            # machine-readable KEY=VALUE, source-able by bash
├── Applications/Ollama.app           # full app bundle (dereferenced copy)
├── home/.ollama/                     # models, keys, config (no cache/, no logs unless included)
├── home/.pi/                         # full agent home (no install/staging)
├── app-support/Ollama/               # ~/Library/Application Support/Ollama
├── brew/Cellar/<formula>/<ver>/      # node + all dylib-dep formulae
├── brew/opt/<formula>  → recorded    # opt symlink targets recorded in manifest (recreated)
├── brew/bin-entries.txt              # brew bin symlinks to recreate (node, npm, npx, corepack…)
├── node-dist/node-v<ver>-darwin-arm64.tar.xz   # official fallback runtime
├── restore-kit/
│   ├── 7zz                           # macOS 7-Zip binary (dequarantined) → offline extraction
│   ├── restore.sh, common.sh, verify.sh
│   └── RESTORE-README.md             # printed instructions when offline
└── project/                          # copy of this repo's scripts/, webapp/, llm-wiki/, README.md
```

Next to the archive, the backup also writes:

```
<name>.manifest.txt      # copy of MANIFEST.txt (readable without extracting)
<name>.sha256            # checksum of the .7z
```

### 3.2 Staging strategy (critical for 61 GB)

- A staging directory is built from **symlinks** pointing at the real data
- `7zz a -l` (`-l` = follow symlinks) compresses through the links → **no double copy** of 61 GB
- Real files (manifest, restore-kit, project copy, node-dist) sit alongside the links
- Staging is deleted on exit (trap SIGTERM/SIGINT for cancellable jobs)

### 3.3 Compression policy

- **Default `-mx=5`** (7-Zip "normal", the recommended level) — GGUF weights are already
  high-entropy binary; `-mx=9` measured gains ≈1–2 % for multi-hour cost on 61 GB
- Level is user-selectable 0 (store) – 9 (ultra) in the web UI and via `--level`
- `-mmt=on` (multithreaded) always

### 3.4 Restore flow

1. Locate `7zz`: `--7zz` arg → `restore-kit/7zz` extracted beside archive → project `bin/` → PATH
2. Extract archive to a temp dir; `xattr -dr com.apple.quarantine` the 7zz binary
3. `source manifest.env`; warn if `ARCH`/macOS mismatch
4. Quit Ollama if running (`osascript`); wait for exit
5. **Safety:** existing targets are *renamed* to `<target>.pre-restore-<ts>` (never deleted) unless `--purge-existing`
6. Copy components back with `ditto` (preserves xattrs + code signatures):
   - `Ollama.app` → `/Applications/` (fresh OS = plain copy, no TCC issue; if replacing an
     existing bundle fails with App Management TCC, print exact manual instruction and continue)
   - `~/.ollama`, `~/.pi`, `~/Library/Application Support/Ollama`
   - brew: `Cellar/<formula>` dirs into `OBD_BREW_PREFIX`, recreate `opt/<f>` relative symlinks
     from manifest, recreate bin entries from `brew/bin-entries.txt`
7. Recreate `/usr/local/bin/ollama` symlink and `~/.local/bin/pi` symlink
   (elevation: try direct → `osascript … with administrator privileges` GUI prompt → clear failure message)
8. Node fallback: if brew restore was skipped/failed and `node-dist/` exists → extract to
   `/usr/local/lib/obd-node-v<ver>` + symlink `/usr/local/bin/node`
9. Launch Ollama (`open -a Ollama`), poll `127.0.0.1:11434` up to 60 s
10. Run `verify.sh`; diff installed model list vs manifest list; write restore report; exit code

### 3.5 Testability contract (env overrides)

Every default path can be overridden so the whole flow is testable without touching the real
install or shipping 61 GB through CI-style runs:

```
OBD_OLLAMA_APP          default /Applications/Ollama.app
OBD_OLLAMA_CLI          default /usr/local/bin/ollama
OBD_OLLAMA_HOME         default $HOME/.ollama
OBD_OLLAMA_APP_SUPPORT  default "$HOME/Library/Application Support/Ollama"
OBD_PI_HOME             default $HOME/.pi
OBD_PI_LAUNCHER         default $HOME/.local/bin/pi
OBD_BREW_PREFIX         default /opt/homebrew (arm64) | /usr/local (x86_64)
OBD_PROJECT_DIR         auto (script dir/..)
OBD_NODE_DIST_URL_DIR   optional mirror for node tarball downloads
Restore-only:
OBD_DEST_PREFIX         prefix all absolute destinations (sandbox e2e tests)
```

---

## 4. File tree (to be built)

```
ollamaBackupDeluxe/
├── LICENSE                     ✅ exists (GPLv3)
├── README.md                   ⬜ full docs + offline restore runbook
├── AGENTS.md                   ✅ LLM agent instructions + wiki schema pointer
├── .gitignore                  ✅ bin/, logs/, *.7z, .DS_Store, cache/, .runtime/
├── start-webapp.sh             ⬜ launcher; self-boots bundled Node if system has none
├── bin/                        ⬜ (gitignored) 7zz binary, cached node-dist
├── logs/                       ⬜ (gitignored) job logs
├── docs/plans/                 ✅ this document
├── scripts/
│   ├── common.sh               ✅ detection, logging, elevation, model-list, size helpers
│   ├── prerequisites.sh        ✅ ensure 7zz + optional node-dist prefetch + component audit
│   ├── backup.sh               ⬜ build kit + compress → .7z
│   ├── restore.sh              ⬜ extract + reinstall + verify
│   └── verify.sh               ⬜ component checks + model diff vs manifest
├── webapp/
│   ├── server.js               ⬜ zero-dependency Node HTTP server
│   └── public/{index.html,style.css,app.js}   ⬜ UI
├── tests/                      ⬜ unit + e2e suite (§14)
├── .github/workflows/          ⬜ ci.yml, release.yml, pages.yml (§13)
└── llm-wiki/                   ⬜ knowledge base (§7)
```

## 4b. Release bundle design (what gets copied to the new MacBook)

The user's procedure is: build a backup kit on the source Mac, download a tagged **release
bundle**, copy *both* to the new Mac, restore offline. Therefore the release bundle must be
**self-bootstrapping on a fresh macOS with zero network**:

```
ollama-backup-deluxe-vX.Y.Z-macos.zip
└── ollama-backup-deluxe/
    ├── start-webapp.sh           # boots UI: uses system Node if present, else
    │                             # extracts runtime/node-<arch>.tar.gz to .runtime/
    │                             # (bsdtar is built into macOS), dequarantines, opens browser
    ├── runtime/
    │   ├── node-v<ver>-darwin-arm64.tar.gz   # official Node dist (~25 MB compressed)
    │   └── node-v<ver>-darwin-x64.tar.gz     # both arches: release must run on any modern Mac
    ├── bin/
    │   └── 7zz                   # official 7-Zip — universal binary (arm64 + x64)
    ├── scripts/                  # backup.sh, restore.sh, verify.sh, common.sh, prerequisites.sh
    ├── webapp/                   # server.js + public/ (zero npm deps)
    ├── llm-wiki/                 # knowledge base travels with the release
    ├── docs/ + README.md + LICENSE
    └── VERSION
```

- `scripts/common.sh` resolves `7zz` for the running arch (`bin/7zz-arm64|7zz-x64`) after
  checking `bin/7zz` and system installs — so the same tree works on Intel and Apple Silicon.
- The web app on a fresh Mac can therefore **run the restore job itself** (it shells out to
  `scripts/restore.sh` with the bundled 7zz). Bash + built-in macOS tools are the only runtime
  requirements of a restore; Node is only needed for the UI.
- Release CI attaches this zip to the GitHub Release for tags `v*`.

---

## 5. Interface specs

### 5.1 CLI scripts

| Script | Usage |
|---|---|
| `prerequisites.sh` | `[--yes] [--skip-node-dist]` — installs/locates 7zz into `bin/`, prefetches node tarball, audits components |
| `backup.sh` | `--dest <dir> [--name <name>] [--level 0-9] [--no-node-dist] [--no-logs] [--exclude-models] [--dry-run]` |
| `restore.sh` | `--archive <file.7z> [--7zz <path>] [--dest-prefix <dir>] [--purge-existing] [--no-start] [--yes]` |
| `verify.sh` | `[--manifest <manifest.env>] [--archive <file.7z>]` — ✓/✗ table, nonzero exit on failure |

All scripts: `set -euo pipefail`, colored log with `OBD` prefix, `--help`.

### 5.2 Web app (zero-dependency, binds `127.0.0.1:8686`)

| Endpoint | Method | Purpose |
|---|---|---|
| `/` + static | GET | UI |
| `/api/system` | GET | component versions, du sizes (cached 60 s), 7zz status, disk free |
| `/api/browse?path&mode=dir\|file` | GET | server-backed file explorer (works in any browser, no FS API) |
| `/api/archive-info?path` | GET | reads `manifest.env` out of archive via `7zz e -so` → preview before restore |
| `/api/backup` | POST | `{destDir, filename, level, includeNodeDist, includeLogs}` → starts job |
| `/api/restore` | POST | `{archive}` → starts job |
| `/api/prereqs` | POST | runs prerequisites.sh as a job |
| `/api/job` | GET | `{running, status, exitCode, log[], startedAt, endedAt}` (polled ~1 s) |
| `/api/job/cancel` | POST | SIGTERM → scripts clean up staging |

Single concurrent job. Logs also tee'd to `logs/<ts>-<type>.log`.

**UI:** dark theme, two hero buttons (BACKUP / RESTORE) → modal dialogs with embedded
file-explorer + options (compression level select, node-dist toggle, logs toggle).
Live log pane with status pill + cancel. System panel with detected versions/sizes.

---

## 6. Design decisions & rationale (ADR summary)

| # | Decision | Rationale |
|---|---|---|
| D1 | Default `-mx=5`, selectable | GGUF blobs incompressible; mx=9 wastes hours for ~1 %. User approved recommended level. |
| D2 | Symlink staging + `7zz a -l` | Avoid duplicating 61 GB to a staging copy. |
| D3 | Self-contained kit (7zz + scripts inside archive) | Offline restore must not depend on brew/network/this repo. |
| D4 | Brew Cellar chain + opt/bin recreation + node-dist fallback | Node is dylib-linked; bare binary insufficient. Tarball = belt-and-suspenders runtime. |
| D5 | Rename-don't-delete on restore | Irreversible-accident prevention; `--purge-existing` is explicit. |
| D6 | `osascript` elevation for `/usr/local/bin` | GUI password prompt works from web-app context; no pre-baked sudo. |
| D7 | Exclude `~/.ollama/cache`, `~/.pi/agent/install/staging`, `.pid` files | Regenerable/ephemeral. |
| D8 | Model list from manifest tree walk | No dependency on server running during backup. |
| D9 | `ditto` for app/data copies | Preserves xattrs, signatures, resource forks. |
| D10 | Zero-dep web app on node:http | Restore machine may have no npm/network; nothing to install. |

---

## 7. llm-wiki knowledge base (per karpathy pattern)

Structure instantiated for this project (schema in `llm-wiki/SCHEMA.md`, referenced by `AGENTS.md`):

```
llm-wiki/
├── SCHEMA.md                    # how the LLM maintains this wiki (ingest/query/lint ops)
├── index.md                     # content catalog: page → one-line summary
├── log.md                       # append-only, grep-parseable "## [date] op | title"
├── overview.md                  # what this system is, thesis
├── sources/llm-wiki-pattern.md  # raw source: karpathy gist (immutable)
├── components/{ollama,pi,node-runtime,seven-zip}.md
├── architecture/{backup-archive-layout,backup-flow,restore-flow,webapp}.md
├── runbooks/{offline-restore,fresh-os-reload}.md
└── reference/{paths,troubleshooting,decisions}.md
```

- Wiki-links `[[page]]` style, Obsidian-compatible; index updated on every ingest
- Initial ingest #1: the karpathy gist (copied verbatim into `sources/`)
- Subsequent ingests: this plan doc, README, post-implementation findings, restore-run reports

---

## 8. Test plan

### 8.1 Automated suite (tests/ — runs in CI and locally)

Zero-dependency harness: `tests/run-tests.sh` (pure bash asserts) + Node built-in `node:test`
for the web app. No bats, no npm installs.

| Suite | File(s) | Covers |
|---|---|---|
| common lib | `tests/unit/test-common.sh` | `obd_model_list` (classic + v2 manifests), `obd_dest` prefix mapping, `human_size`, `sanitized_key`, `obd_find_7zz` order, manifest env round-trip |
| 7z mechanism | `tests/unit/test-7zip.sh` | symlink dereference via `-l` into expected archive paths; `7zz e -so` manifest extraction; store vs level flags |
| backup e2e | `tests/unit/test-backup.sh` | sandbox fixtures via `OBD_*` overrides → archive layout, manifest.env keys, model list, sha256 sidecar, `--dry-run`, cancel leaves no staging behind |
| restore e2e | `tests/unit/test-restore.sh` | `OBD_DEST_PREFIX` sandbox: full extract→copy→symlink recreation→verify pass; pre-existing targets renamed not deleted; app-support + brew cellars + node fallback |
| verify | `tests/unit/test-verify.sh` | ✓/✗ detection against sandbox trees; model diff mismatch → nonzero exit |
| webapp | `tests/webapp/server.test.js` | `node:test`: /api/system, /api/browse (dir+file modes, path safety), /api/archive-info, job lifecycle (start→log→done→cancel), static serving |

Run: `tests/run-tests.sh` (bash suites; macOS required for e2e) and `node --test tests/webapp/`.

### 8.2 The user's real-world procedure (documented, executed manually)

1. On **this MacBook**: `prerequisites.sh` → `start-webapp.sh` → BACKUP (61 GB kit to external
   drive or AirDrop-able location). Verify `<name>.7z`, `.sha256`, `.manifest.txt` exist.
2. Download/copy the latest **release bundle** zip (built by tag CI, §9) next to the kit.
3. On the **new MacBook** (wifi off, fresh OS): unzip release → `start-webapp.sh`
   (self-boots bundled Node + bundled 7zz) → RESTORE → pick the `.7z` → confirm → done.
   Fallback with no Node at all: `unzip` the kit's `restore-kit/restore.sh` via the bundled
   7zz and run it in Terminal — restore itself never needs Node.
4. Re-enable Ollama "Start at Login" (Login Items), open Pi, run a model → done.

This procedure is validated by §8.1's sandbox e2e (same code paths, fixture-sized data) and by
the release bundle e2e test in CI (unpack release zip on a macOS runner with no brew/network
assumptions, run restore against sandbox fixtures).

### 8.3 Real backup (user-run, not automated)

Full 61 GB kit to external drive; spot-check by listing archive contents.

---

## 9. CI/CD (GitHub Actions)

Three workflows:

### `.github/workflows/ci.yml` — every PR and every push to main

| Job | Runner | Steps |
|---|---|---|
| `lint` | ubuntu-latest | shellcheck all `scripts/*.sh` and `tests/**/*.sh`; `bash -n` syntax pass |
| `unit-common` | macos-14 (arm64) | `tests/run-tests.sh --suite common,7zip` |
| `e2e-backup` | macos-14 | sandbox fixtures → `backup.sh` → structural asserts on archive |
| `e2e-restore` | macos-14 | e2e backup artifact → `restore.sh` with `OBD_DEST_PREFIX` → `verify.sh` green |
| `webapp` | macos-14 | `node --test tests/webapp/` against current LTS Node |
| `release-smoke` | macos-14 | build the §4b bundle (same script release.yml calls), unzip to clean dir, run `start-webapp.sh` in headless mode (no browser), hit `/api/system` |
| `coverage` | macos-14 | `tests/coverage.sh` — full suite under kcov (bash line coverage incl. child processes) + node:test coverage → `coverage/coverage-report.md`, uploaded as artifact and echoed to the job summary |

Notes: public repo ⇒ macOS runners are free; scripts only need bash + system tools;
`prerequisites.sh` acquires 7zz in CI (network available there) and tests assert from `bin/`.
GitHub API calls (7-Zip release lookup) authenticate with `GITHUB_TOKEN` and fall back to a
pinned tag when the API is unavailable — anonymous runner IPs exhaust the 60 req/h limit fast.

Notes: public repo ⇒ macOS runners are free; scripts only need bash + system tools;
`prerequisites.sh` acquires 7zz in CI (network available there) and tests assert from `bin/`.

### `.github/workflows/release.yml` — tags `v*`

1. Trigger: `on: push: tags: ['v*']`
2. Checkout → run the full test suite (fail the release on red)
3. `scripts/build-release.sh --version "${GITHUB_REF_NAME#v}"` → `dist/ollama-backup-deluxe-vX.Y.Z-macos.zip`
   (embeds: both-arch 7zz via prerequisites, both-arch official Node tarballs, scripts, webapp,
   llm-wiki, docs, VERSION file)
4. `softprops/action-gh-release` attaches the zip + sha256 to the Release, marks it as latest

### `.github/workflows/pages.yml` — push to main

Publishes the **web app UI at the site root** plus **llm-wiki + docs** as a browsable site:
1. Stage `webapp/public/*` at the site root (relative assets; UI auto-detects engine presence),
   `llm-wiki/**`, `docs/**`, `README.md`; bake `config.js` with the repo URL (release links)
2. Jekyll renders the markdown; app files pass through verbatim
3. UI modes: local (same-origin engine) / remote (Pages UI drives the local engine via
   opt-in `OBD_ALLOWED_ORIGIN` CORS) / guide (setup walkthrough + latest-release download)
4. `actions/upload-pages-artifact` + `actions/deploy-pages`

### Tagging a release (human workflow)

```
git tag v1.0.0 && git push origin v1.0.0   # → release.yml builds + publishes automatically
```

---

## 10. Unit test harness design

- `tests/lib/assert.sh`: `assert_eq`, `assert_contains`, `assert_file_exists`, `assert_symlink_target`,
  `assert_exit` — colored TAP-ish output, fail-fast optional, exit count summary.
- `tests/lib/sandbox.sh`: `make_fixture_tree <dir>` builds a miniature replica of the real layout
  (fake Ollama.app with a working `ollama` stub binary, `~/.ollama` with 2 fake models incl.
  manifests-v2 entries, fake `~/.pi` with launcher + install/current-version, fake brew Cellar
  with node + 2 dylib formulae, fake Application Support) — used by backup/restore/verify e2e.
- `OBD_TEST_TMP` isolation, cleanup traps, no writes outside `/tmp` + project `tests/.tmp`.
- `tests/run-tests.sh [--suite <name>...] [--list]` — suite discovery, per-suite timing, summary.
- CI workflow detail: §9; workflow list: §11 checklist and `.github/workflows/`.

---

## 11. Task checklist

- [x] Inspect system, capture inventory (§2)
- [x] Fetch karpathy llm-wiki pattern → `llm-wiki/sources/`
- [x] Write this plan (incl. release bundle §4b, CI/CD §9, tests §10, offline procedure §8.2)
- [x] `.gitignore`, `AGENTS.md`
- [x] `scripts/common.sh`
- [x] `scripts/prerequisites.sh` → install 7zz into `bin/` (verified live: 7zz 26.04 + node tarball cached)
- [x] `scripts/backup.sh`
- [x] `scripts/restore.sh`
- [x] `scripts/verify.sh` (real machine: 11/11 checks, 7 models)
- [x] `scripts/build-release.sh` (verified: 62 MB universal bundle, boots bundled Node)
- [x] `webapp/server.js` + `webapp/public/*`
- [x] `start-webapp.sh` (self-booting bundled Node runtime — verified on node-less PATH)
- [x] `tests/` harness + all suites — 114 checks green locally (§10)
- [x] `.github/workflows/{ci,release,pages}.yml`
- [x] `README.md`
- [x] `llm-wiki/*` (schema, index, log, 16 pages)
- [x] ShellCheck clean across scripts + tests (CI parity)
- [x] Addendum A: harness expansion + devcontainer kit (implemented, 179 tests green)
- [ ] User-run: real 61 GB kit to external drive (§8.3)
- [ ] First tagged release `v0.1.0` → verify release.yml artifact
- [ ] Real restore drill on target hardware

---

## 12. Addendum A — harness expansion + devcontainer kit (2026-10-12, post-v0 planning)

**Harness expansion.** Backups now also cover Claude Code (native install: `~/.local/share/claude`
versioned binaries, absolute launcher symlink, `~/.claude` data) and OpenCode
(`~/.opencode` binary + post-first-run config/session/state incl. plugin node_modules; cache
excluded; selective slice of `~/.config`), plus shell rc files for PATH wiring.

**Devcontainer kit (secondary restore).** Every backup additionally writes
`<name>-devcontainer.tar.gz`: Linux ollama CLI (version-pinned, extracted from the official
tar.zst), Node/Claude/OpenCode Linux builds (claude checksum-verified via the official manifest),
Linux 7zz, configs, and a Linux restore script. Restored inside a Linux devcontainer it installs
the toolset with NO models and wires `OLLAMA_HOST` so `ollama launch pi` / `ollama launch
claude` talk to the Mac host over the network. Capture happens on the host at backup time
(cached, best-effort per payload, `--no-devcontainer` to skip); restore is fully offline.
`devcontainer/` holds an example validation container. Constraint: glibc images.

## 12. Risks & mitigations

| Risk | Mitigation |
|---|---|
| App Management TCC blocks replacing `/Applications/Ollama.app` on restore | Fresh-OS case = new copy (allowed); replacement failure → clear manual step in output |
| `/usr/local/bin` not writable | osascript elevation with GUI prompt; explicit fallback message |
| macOS version/arch drift on restore target | Manifest records both; restore warns (arm64 tarball won't run on Intel) |
| 7zz quarantined by Gatekeeper on fresh Mac | `xattr -dr com.apple.quarantine` step in restore; kit files copied via disk, not browser, so usually clean |
| Disk space during backup | Pre-flight `df` check vs estimated source size + 10 % margin |
| Job killed mid-backup | Trap SIGTERM/SIGINT → remove staging dir; archive written to `.part` then renamed |
| Sensitive files (auth.json, id_ed25519) in archive | Documented: keep backup media encrypted (user choice; 7z `-p` supported via `--passphrase` env) |
