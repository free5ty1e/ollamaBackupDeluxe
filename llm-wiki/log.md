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
