# runbooks/offline-restore

Purpose: the procedure to follow when the internet is gone and inference must come back.

## Before backing up (source side)

Quit the CLI harnesses that hold SQLite stores (OpenCode writes `opencode.db-wal` while running;
Claude/others keep small state) — the backup script quits Ollama automatically; for OpenCode,
just don't run it during the backup.

## What you need (all verified offline-capable)

1. The backup kit: `<name>.7z` (+ its `.sha256` and `.manifest.txt` sidecars, nice to have).
2. EITHER the release bundle `ollama-backup-deluxe-vX-macos.zip` (for the web app) — or nothing
   else at all for the pure-Terminal path.

## Path A — web app (nicer)

1. Unzip the release bundle anywhere (e.g. Desktop).
2. `./start-webapp.sh` — if the Mac has no Node, the bundle extracts its bundled runtime to
   `.runtime/` on first launch (needs no network; see [[runbooks/fresh-os-reload]]).
3. RESTORE → Browse → pick the `.7z` → check the preview (host, versions, model count) → confirm.
4. Watch the log; wait for `Restore complete`.

## Path B — Terminal only (zero prerequisites beyond macOS)

```bash
# the kit contains its own extractor and restore script; get them out:
#   (7zz is inside the kit, so first extract with ANY tool that reads .7z —
#    e.g. Keka/The Unarchiver if present — or the release bundle's bin/7zz)
./bin/7zz x "<path>/my-kit.7z" -o/tmp/obd-kit
bash /tmp/obd-kit/restore-kit/restore.sh --archive "<path>/my-kit.7z"
```

Enter the admin password when prompted (one step, for `/usr/local/bin/ollama`).

## After any restore

- Re-enable Ollama → Settings → "Start at Login" (Login Items don't travel with the filesystem).
- `scripts/verify.sh --manifest <kit>/manifest.env --expect-server` for a full audit.
- Old installs are at `*.pre-restore-<timestamp>` — delete them once happy.
- Sanity run: `ollama list` matches the manifest; `pi --version`, `claude --version`,
  `opencode --version` all match; a small model responds.
- If a `.zshrc.obd-backup` was written, merge its PATH lines into your live `.zshrc`.

## If something is broken

See [[reference/troubleshooting]]; worst case, re-run restore with `--purge-existing`.

Related: [[architecture/restore-flow]], [[runbooks/fresh-os-reload]], [[components/ollama]].
