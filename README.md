# Ollama Backup Deluxe

**Fully offline-restorable backups of your local LLM inference stack on macOS.**

One tool, two functions — both available in a local web app and on the command line:

1. **BACKUP MY CURRENT LOCAL INFERENCE SETUP** → a self-contained `.7z` "backup kit"
2. **RESTORE A LOCAL INFERENCE SETUP** → rebuild everything on a fresh Mac, **zero internet**

What gets captured (verified paths, see `llm-wiki/reference/paths.md`):

| Component | What | Why |
|---|---|---|
| **Ollama** | `/Applications/Ollama.app`, `~/.ollama` (models, keys, config), `~/Library/Application Support/Ollama` (db) | app + CLI + all model weights |
| **Pi coding agent** | `~/.pi` (managed install, settings, auth, sessions), `~/.local/bin/pi` launcher | your harness, versions pinned |
| **Claude Code** | `~/.local/share/claude` (versioned runtime), `~/.claude` (settings, sessions), launcher symlink | harness #2, self-contained binaries |
| **OpenCode** | `~/.opencode` (binary + plugin runtime), `~/.config/opencode`, `~/.local/share/opencode` (session db), `~/.local/state/opencode` | harness #3, sessions included |
| **Node.js** | the full Homebrew Cellar chain behind `node` **plus** the official node dist tarball | Pi's runtime; brew node is dylib-linked so a bare binary is not enough |
| **Shell rc files** | `~/.zshrc`, `~/.zprofile`, `~/.zshenv`, `~/.bashrc`, `~/.bash_profile` | PATH wiring (`~/.local/bin`, `~/.opencode/bin`, brew) — launchers are useless without it |
| **This tool** | its own extractor (7zz), restore scripts, and a project copy | the backup restores itself — no Homebrew, no npm, no network |
| **Devcontainer kit** | `<name>-devcontainer.tar.gz` next to the kit: Linux ollama CLI + Node + Claude + OpenCode + configs + a Linux restore script | secondary restore: a Linux devcontainer uses **this Mac's** Ollama over the network (`ollama launch pi`, `ollama launch claude`) — no models installed there |

The archive also contains `MANIFEST.txt` (human) + `manifest.env` (machine): versions, host,
architecture, the exact model list, sizes, and options used.

---

## Quick start (source Mac)

```bash
# one-time setup: installs 7zz into ./bin, caches the Node fallback tarball, audits the stack
./scripts/prerequisites.sh

# launch the web app (http://127.0.0.1:8686, local only)
./start-webapp.sh
```

Then click **BACKUP MY CURRENT LOCAL INFERENCE SETUP**, pick a destination folder
(e.g. an external drive), name the archive, and go. Files produced:

```
<name>.7z             the backup kit (self-contained)
<name>.7z.sha256      checksum
<name>.manifest.txt   readable summary (no extraction needed)
```

### CLI equivalent

```bash
scripts/backup.sh --dest /Volumes/Backup --name my-kit           # 7z level 5 (recommended)
scripts/backup.sh --dest /Volumes/Backup --level 9               # ultra (slow, ~no gain on weights)
scripts/backup.sh --dry-run --dest /tmp --name probe             # inspect without writing
scripts/verify.sh                                                # audit current machine
```

## Quick start (target Mac — no internet required)

1. Copy the **release bundle** (`ollama-backup-deluxe-vX.Y.Z-macos.zip` from GitHub Releases,
   built automatically when you push a `v*` tag) **and** the `.7z` kit to the machine.
2. Unzip the bundle, run `./start-webapp.sh`.
   - No Node on the machine? The bundle ships official Node tarballs and extracts one to
     `.runtime/` on first launch — completely offline.
3. Click **RESTORE A LOCAL INFERENCE SETUP**, pick the `.7z`, confirm, watch the log.
4. Re-enable "Start at Login" for Ollama in its settings, open Pi, run a model.

## Secondary restore: Linux devcontainers (no models, network to this Mac)

Every backup (unless `--no-devcontainer`) also writes `<name>-devcontainer.tar.gz`: Linux builds
of the ollama CLI, Node, Claude Code and OpenCode (captured **at backup time, while online**;
cached in `cache/devcontainer/` so later backups are fast), plus their configs and a Linux
restore script with a bundled Linux 7zz. Inside the devcontainer, fully offline:

```bash
tar -xzf <name>-devcontainer.tar.gz && cd obd-devcontainer
./restore-devcontainer.sh --archive /kit/<name>.7z [--ollama-host http://host.docker.internal:11434]
```

Then `ollama list`, `ollama launch pi`, `ollama launch claude` — the container talks to the
host's Ollama server (`OLLAMA_HOST`, wired into `.bashrc`/`.zshrc`). Host prerequisite: expose
Ollama to the network (app settings). Payloads are glibc builds — Debian/Ubuntu-style images
(see `devcontainer/README.md` for a ready-made validation container).

### CLI restore (works even without Node)

```bash
# the kit contains its own extractor:
#   (extract anywhere) then:
bash restore-kit/restore.sh --archive /Volumes/Backup/my-kit.7z
```

Restore behavior: quits Ollama → **renames** existing installs aside
(`*.pre-restore-<timestamp>`, never deletes; `--purge-existing` to opt out) → reinstalls app,
data, Pi, Claude, OpenCode, and the Node chain → recreates symlinks → restores shell rc files
(existing ones are kept and the kit's copy is written as `<name>.obd-backup` for you to merge) →
starts Ollama → verifies everything against the manifest. `/usr/local/bin` needs an admin
password once (macOS GUI prompt).

---

## The web app

- Binds to `127.0.0.1:8686` only. **Zero npm dependencies** — nothing to install, ever.
- Server-backed file explorer for choosing destinations and archives (works in any browser).
- Live job log with cancel; archive preview (versions + model count) before restoring.
- Jobs are also tee'd to `logs/`.

### GitHub Pages copy (static)

The project's Pages site serves the **same UI** (relative assets, three auto-detected modes):

1. **Local** — opened from the engine itself: full function.
2. **Remote** — the Pages UI *drives your local engine*: the guide offers a one-command setup
   (`curl -fsSL <pages>/bootstrap.sh | bash` — downloads the latest release, installs to
   `~/.ollama-backup-deluxe`, starts the engine pre-authorized for the Pages origin), after which
   the hosted page auto-connects and gives full backup AND restore from the browser.
   Manual equivalent: `OBD_ALLOWED_ORIGIN="https://<owner>.github.io" ./start-webapp.sh`
   (a green "connected" banner appears; never set the origin to `*`).
3. **Guide** — no engine reachable: a setup walkthrough with a direct
   **Download the latest release** link, the two-line start command, and the wiki/docs beside it.

Pages deploys on every push to `main` (`.github/workflows/pages.yml`); the app UI is served at
the site root with `llm-wiki/` and `docs/` rendered beside it.

Staging note: backups stage **symlinks**, not copies — the 61 GB of models are read through the
links during compression, so there is no giant temp folder. The tiny staging tree (symlinks +
manifest + embedded tool copy) defaults to the system temp dir; pin it with
`--staging-dir <dir>` or the web app's "Advanced" field.

## Compression note

Default is 7-Zip level **5** ("normal" — the recommended setting). Model weights are
high-entropy binary data; level 9 spends hours for ~1–2 % on a 60 GB library. Levels 0–9 are
selectable in the UI / `--level` if you want to trade time anyway.

## For agents and developers

`llm-wiki/introduction.md` is the briefing document — it doubles as an initial prompt for any
coding agent joining the project (purpose, structure, binding rules, first five actions). The
knowledge base under `llm-wiki/` is maintained by the coding agent per its `SCHEMA.md`.

## Development

```bash
tests/run-tests.sh              # all suites (bash e2e + webapp node:test)
tests/run-tests.sh --list       # list suites
tests/coverage.sh               # full suite + coverage report (kcov bash line
                                # coverage + node:test coverage → coverage/coverage-report.md)
shellcheck scripts/*.sh         # lint (CI enforces, pinned to 0.11.0)
```

Sandbox contract: every path is overridable via `OBD_*` env vars (`scripts/common.sh`), and
`OBD_DEST_PREFIX` redirects all restore destinations — that's how the full backup→restore cycle
is tested end-to-end without touching the real install. See
`docs/plans/2026-10-12-initial-implementation-plan.md` for the design (§8 tests, §9 CI/CD, §4b release bundle).

### CI/CD

- **Every PR / push to main** → ShellCheck + unit + e2e + webapp + release-smoke (`.github/workflows/ci.yml`)
- **Tag `v*`** → full suite, then the release bundle is built and attached to a GitHub Release (`release.yml`)
- **Push to main** → llm-wiki + docs published to GitHub Pages (`pages.yml`)

```bash
git tag v1.0.0 && git push origin v1.0.0    # → release CI builds the bundle
```

## Security notes

- The kit contains `~/.ollama/id_ed25519` and Pi's `auth.json` (API keys). **Keep backup media
  encrypted** (FileVault'd disk or `7z -p` via `scripts/backup.sh --help` customization).
- The web app listens on localhost only and runs scripts as your user — treat it like a terminal.

## License

GPLv3 — see `LICENSE`. 7-Zip (LGPL/BSD) and Node.js (MIT) are downloaded at setup time from
their official releases; nothing is redistributed in this repository.
