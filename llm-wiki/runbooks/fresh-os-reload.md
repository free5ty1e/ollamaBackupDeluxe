# runbooks/fresh-os-reload

Purpose: full walkthrough for the actual scenario — brand-new macOS on the new MacBook, wifi off.

## One-time (on the SOURCE Mac, online)

1. `./scripts/prerequisites.sh` (installs 7zz into `bin/`, caches the Node fallback tarball).
2. `./start-webapp.sh` → BACKUP → external drive destination → wait for `Backup complete`.
3. `git tag v1.0.0 && git push origin v1.0.0` → CI builds `ollama-backup-deluxe-v1.0.0-macos.zip`
   and attaches it to the GitHub Release; download it (needs network — do this BEFORE losing it).
4. Copy to the new Mac (external drive/AirDrop): the release zip + the `.7z` kit.

## On the NEW MacBook (offline, fresh macOS)

1. Unzip the release bundle. First launch does two self-bootstrap steps, no network needed:
   - extracts the bundled official Node tarball for this arch to `.runtime/node-current`
     (macOS `bsdtar` reads the `.tar.xz` natively),
   - the bundled universal `bin/7zz` is already executable (dequarantined during extraction).
2. `./start-webapp.sh` → browser opens on `http://127.0.0.1:8686`.
3. RESTORE → pick the kit → confirm → wait. The restore quits nothing (no Ollama yet), installs
   the app + `~/.ollama` (models!) + `~/.pi` + the Node brew chain + symlinks, starts Ollama,
   and verifies the model list against the kit manifest.
4. Post-restore manual bits (see [[runbooks/offline-restore]]): re-enable Start at Login;
   delete `*.pre-restore-*` asides (none on a fresh machine); launch Pi.

## If the release bundle is unavailable

Path B of [[runbooks/offline-restore]] — the kit alone suffices via Terminal (any `.7z`-capable
tool + the embedded `restore-kit/`).

## Acceptance checklist

- [ ] `ollama list` shows the manifest's model set
- [ ] a model generates a completion (Ollama app running, API healthy)
- [ ] `pi --version`, `claude --version`, `opencode --version` match the manifest
- [ ] `scripts/verify.sh --manifest … --expect-server` exits 0
- [ ] old-machine asides removed; backup media moved to cold storage

Related: [[architecture/restore-flow]], [[components/node-runtime]], [[reference/troubleshooting]].
