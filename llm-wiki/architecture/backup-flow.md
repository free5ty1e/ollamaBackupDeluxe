# architecture/backup-flow

Purpose: how backup.sh turns the live system into a kit — stages, guards, options.

## Stages

1. **Preflight** — resolve paths (OBD_* overrides), require 7zz, require `~/.ollama`; measure
   component sizes (`du -sk`); refuse to run if destination free space < estimate × 1.1.
2. **Inventory** — detect versions (ollama binary, pi launcher, node via `obd_detect_node`),
   enumerate models from the manifest trees (no server needed — see [[components/ollama]]).
3. **Staging** (`mktemp -d` under `TMPDIR` — pinnable via `--staging-dir` / the web app's
   "Advanced" field; trap-cleaned on EXIT/INT/TERM) — a tree of **symlinks** to the real
   data plus real small files (manifest, restore-kit, project copy). 7zz's default `a` behavior
   dereferences the links (see [[components/seven-zip]]), so 61 GB is read once, never copied —
   there is no large temp folder to size or clean.
   Per-entry links let us exclude `~/.ollama/cache`, optional logs/models, and `install/staging`.
4. **Manifests** — `manifest.env` (contract: [[architecture/backup-archive-layout]]) + `MANIFEST.txt`.
5. **Compress** — `7zz a -mx=<level> -mmt=on -bso0 -bsp1` → `<out>.part.7z`, then atomic rename;
   progress CR-lines sanitized into the job log. Sidecars: `.sha256` (`shasum -a 256`), `.manifest.txt`.
6. **Restart** — if backup quit Ollama (default, for db consistency), relaunch it.

## Options

`--dest <dir>` (required) · `--name` (default `ollama-backup-YYYYMMDD-HHMMSS`) · `--level 0-9`
(default **5** — rationale: [[reference/decisions]]) · `--no-node-dist` · `--no-logs` ·
`--exclude-models` · `--no-quit` (don't stop/restart Ollama) · `--dry-run` (builds staging +
manifest, writes nothing).

## Consistency note

Ollama is quit by default so `db.sqlite{,-wal}` in Application Support is captured quiescent.
`--no-quit` trades consistency for zero disruption (models dir is append-only blob storage, so
weight data is safe either way; the db is what benefits from the quit).

Related: [[architecture/backup-archive-layout]], [[architecture/restore-flow]], [[components/pi]].
