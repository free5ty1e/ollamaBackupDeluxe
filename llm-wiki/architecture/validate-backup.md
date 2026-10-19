# architecture/validate-backup

Purpose: `scripts/validate-backup.sh` proves a kit is restorable WITHOUT restoring it — the
automation behind the web app's VALIDATE button, the "Validate after backup" checkbox, and
"Validate before restoring".

## Checks

1. Sidecar presence (`.sha256`; `.manifest.txt` advisory)
2. SHA256 of the whole archive vs sidecar (accepts hash-only and standard `<hash>  <name>` formats)
3. **`7zz t`** — every CRC in the archive (the expensive check; reads everything) — `--quick` skips
4. `manifest.env`: required keys, MODELS_COUNT > 0, arch match (warn)
5. Structure: required entries (app, data, harnesses, restore-kit, project copy) + optional
   entries (claude, opencode, brew chain, node-dist) and the devcontainer sidecar (advisory)
6. Counts vs the live machine (when present): blobs exact match; manifests via a **directional
   set comparison** — kit missing live files = FAIL (kit outdated); kit extras = advisory
   (Ollama prunes/migrates legacy manifests-v2; the kit is a snapshot)
7. Content-addressed sampling: N smallest blobs extracted; `sha256(blob) == sha256-<hash>` name
8. Spot check: extracted ollama binary byte-identical to the live install

## Web app wiring

- `POST /api/validate {archive}` → job running the validator (log streams the check table)
- Backup modal "Validate after backup" → `backup.sh --validate` (runs inline after sidecars;
  failure exits 5 — the kit must not be trusted)
- Restore modal "Validate before restoring" → `restore.sh --validate-archive` (runs before
  extraction; failure aborts with nothing changed)

## Gotchas baked in

- 7zz `-ba` listing cannot distinguish dirs from files (no trailing slashes) → manifest counting
  extracts the tiny manifests tree and uses `find -type f`
- `7zz e` FLATTENS paths — use `x` when paths matter
- macOS bash 3.2: no `"${arr[@]}"` on empty arrays under `set -u`; multibyte chars (`—`) after
  `$var` are parsed as part of the name ([[reference/troubleshooting]])
- Live comparisons are conditional: validating away from the source machine skips them

Related: [[architecture/backup-flow]], [[architecture/restore-flow]], [[reference/troubleshooting]].
