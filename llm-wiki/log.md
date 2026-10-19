# llm-wiki log

Append-only. Format: `## [YYYY-MM-DD] <op> | <title>` — parseable with
`grep "^## \[" log.md | tail -5`.

## [2026-10-12] ingest | LLM wiki pattern (karpathy gist)
- Fetched via curl (local ollama web_fetch endpoint errored); stored verbatim in sources/.
- Adopted: schema/index/log triad, LLM-owns-wiki, sources immutable.

## [2026-10-12] ingest | Initial implementation plan (docs/plans/2026-10-12)
- Full system inventory captured by live inspection (see [[components/*]] pages).
- Key designs: symlink staging + default 7z level 5; self-contained kits; OBD_* sandbox contract.
- User addenda: release bundle must self-bootstrap Node on a fresh Mac; CI for PRs; tag-triggered
  releases; GitHub Pages for this wiki; unit test suite; user's real procedure = backup here →
  copy release + kit to new Mac → restore offline.

## [2026-10-12] build | Implementation session 1
- Built scripts/{common,prerequisites,backup,restore,verify,build-release}.sh, webapp (zero-dep),
  tests (bash harness + node:test), workflows (ci/release/pages), README.
- Bugs found by the test suite and fixed (details: [[reference/troubleshooting]]):
  `$MAC_ARCH…` var-name eating, SIGPIPE via `grep -q`/`head` under pipefail, `-l` switch not
  supported (default 7zz dereferences symlinks anyway), `$'\0'` glob matching everything,
  `((PASS++))` returning 1 under set -e, obd_dest catch-all semantics, 7zz mac asset being
  arch-agnostic, release bundle missing start-webapp.sh, node dist .tar.gz→.tar.xz swap (114→62 MB).
- Verified live: prerequisites (7zz 26.04 + node v26.11.1 tarball cached), full e2e backup→restore
  in sandbox, webapp job through API, release bundle boots with bundled Node on a PATH without node.

## [2026-10-12] build | Hardening pass (shellcheck + release)
- Installed shellcheck 0.11.0; scripts + tests fully clean (fixed logger printf arg shape,
  directive placement SC1126, dynamic-source SC1091, glob ls→find/compgen).
- Full suite after refactor: 114/114 green. Real-machine verify: 11/11 (Ollama 0.40.3, 7 models,
  1639 blobs, Pi 1.1.0, node v26.11.1, server healthy).
- Release bundle rebuilt with README + llm-wiki included; universal bin/7zz confirmed via lipo.

## [2026-10-12] ingest | Harness expansion: Claude Code + OpenCode added to backups
- User request: fresh MacBook should boot with pi AND claude AND opencode (all local-model capable).
- Inspected live installs: claude native (versions/ + absolute launcher symlink + ~/.claude),
  opencode (self-contained ~/.opencode/bin). See [[components/claude]], [[components/opencode]].
- Also captured shell rc files (PATH wiring gap) — D13. OpenCode first-run data followed:
  config/node_modules (61 MB × 2, offline reinstall needs them), session db, state; cache excluded;
  selective slice of ~/.config (other apps live there) — D14.
- Tests 146→green incl. claude/opencode restore + .obd-backup merge semantics.

## [2026-10-12] build | Devcontainer kit (secondary restore)
- New: capture-devcontainer.sh (host-side, cached Linux payloads: ollama CLI from official
  tar.zst — 1.4-1.6 GB downloaded once, bin/ollama extracted; node/claude/opencode/7zz Linux
  builds; claude checksum-verified via downloads.claude.ai manifest) and restore-devcontainer.sh
  (container-side: toolset only, OLLAMA_HOST wiring, no models, exec-checks guarded by OS).
- Backup now also writes <name>-devcontainer.tar.gz (plain tar.gz — container opens it with
  built-in tar; bundles Linux 7zz to read the main .7z). --no-devcontainer / OBD_SKIP_DC opt-outs.
- devcontainer/ example validation container added; webapp gained backup checkbox + restore
  target select (machine/devcontainer). Tests +33 (fake payloads, no downloads). 179 total green.
- Gotchas fixed: OBD_CACHE_DIR not overridable; bash globs skip dotfiles (home-shell); tar lost
  exec bit on fake payloads (chmod defensively after extraction).

## [2026-10-12] build | GitHub Pages web app deployment
- Pages now deploys the web app UI at the site root (same public/ files, relative assets) with
  llm-wiki + docs beside it; config.js bakes the repo URL for guide-mode release links.
- UI auto-detects three modes: local / remote (Pages UI drives local engine via opt-in
  OBD_ALLOWED_ORIGIN CORS — per-origin, never *) / guide (setup walkthrough, 8s auto-connect).
- pages.yml rewritten (app at root, Jekyll renders knowledge base); server.js gained CORS +
  OPTIONS preflight handling; guide/connected banners in the UI.
- Tests: webapp suite +2 (CORS preflight, relative assets + guide markup). 181 + 10 green.

## [2026-10-12] ingest | introduction.md — the wiki's entry-point briefing
- Added [[introduction]] as the initial prompt for any new agent/developer: project, purpose,
  usage paths (source-mac backup, fresh-mac restore, devcontainer, verify), repo structure,
  pointers (AGENTS.md rules, plan, README, wiki pages), current state, first five actions.
- index.md now lists it under a ⭐ START HERE section at the top; SCHEMA page map and AGENTS.md
  point to it as well.

## [2026-10-12] build | CI fixes + coverage pipeline
- First CI runs exposed: Node 22 can't expand directory args in `node --test` (use explicit file),
  ubuntu shellcheck drift vs local 0.11 (pinned in CI lint job), GitHub API 403 on runner IPs
  (obd_gh_api auth via GITHUB_TOKEN + pinned 7zz fallback tag), webapp test accidentally ran the
  real devcontainer capture (OBD_SKIP_DC=1 + devcontainerKit:false in test env).
- coverage.sh: kcov (PS4 method traces CHILD scripts — backup.sh 90.2%, restore.sh 79.0%,
  common.sh 72.2%, verify.sh 65.7% → bash total 78.6%) + node --experimental-test-coverage
  (server.js 100%) → coverage/coverage-report.md, CI artifact + step summary. kcov DEBUG method
  fails headless; PS4 works.
- kcov run exposed a REAL bug: brew's npm global home lives in $prefix/lib/node_modules —
  OUTSIDE the Cellar — so Cellar-only restore left bin/npm dangling. Now captured (brew/
  lib-node-modules) and restored via ditto-merge; fixture mirrors real layout; tests green.

## [2026-10-12] build | staging-dir option + Pages one-command bootstrap
- Clarified/improved staging: it is symlink-only (no 61 GB temp copy); location now pinnable via
  backup.sh --staging-dir and the webapp Advanced field (server passes it through).
- scripts/bootstrap-remote.sh: Pages-baked one-command setup (curl … | bash) — downloads latest
  release via API (page-scrape fallback), installs to ~/.ollama-backup-deluxe, starts the engine
  with OBD_ALLOWED_ORIGIN preset so the hosted UI auto-connects for full backup/restore.
  Guide mode now shows the copyable one-liner with a copy button; D17 recorded.

## [2026-10-12] build | validate-backup.sh + web app validate wiring; first REAL kit validated
- User's first real 51 GB backup (ollama-backup-20261016-224704.7z) validated end-to-end:
  sha256 match, full CRC pass, 16 structural entries, 1639/1639 blobs, 7/7 manifest files,
  3 content-addressed blob samples verified, ollama binary byte-identical. ALL GREEN.
- scripts/validate-backup.sh codifies the procedure (18 checks); web app: VALIDATE button,
  POST /api/validate, "Validate after backup" (--validate) and "Validate before restoring"
  (--validate-archive) checkboxes; backup --validate exits 5 on failed validation.
- Sidecar .sha256 now standard "<hash>  <name>" (shasum -c compatible); validator accepts both.
- Fixed from the real backup log: obd_gh_api empty-array crash on macOS bash 3.2 (set -u),
  silent curl failures in dc capture (stderr now visible), em-dash-after-$var parsing bug.
- Directional live comparison: kit extras = advisory (Ollama pruned manifests-v2 after the
  user's backup — real observation), kit missing live pulls = fail.
- Tests: 202 green (test-validate: 19 checks incl. corrupt/truncated/mismatch/non-OBD kits).
