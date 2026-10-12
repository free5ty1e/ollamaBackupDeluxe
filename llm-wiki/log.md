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
