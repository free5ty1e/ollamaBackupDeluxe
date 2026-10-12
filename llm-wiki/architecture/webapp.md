# architecture/webapp

Purpose: the zero-dependency local web app that wraps backup/restore.

## Constraints

- **Zero npm dependencies** — built-in `node:http` only. The restore machine may have no npm,
  no cache, no network; there must be nothing to install ([[reference/decisions]]).
- Binds `127.0.0.1:8686` (`OBD_PORT` to change). Local-only by design.
- Needs Node only for the UI; the release bundle self-bootstraps it ([[runbooks/fresh-os-reload]]).

## API surface

| Endpoint | Method | Purpose |
|---|---|---|
| `/`, `/style.css`, `/app.js` | GET | UI |
| `/api/system` | GET | component versions, cached `du` sizes (60 s cache — 61 GB du is slow), model count, disk free, 7zz status |
| `/api/browse?path&mode=dir\|file` | GET | server-backed file explorer; file mode filters to `.7z`; non-absolute paths fall back to `$HOME` |
| `/api/archive-info?path` | GET | reads `manifest.env` out of the archive via `7zz e -so` → pre-restore preview (host, versions, model count, sizes) |
| `/api/backup` | POST | `{destDir, filename, level, includeNodeDist, includeLogs}` → starts `scripts/backup.sh` |
| `/api/restore` | POST | `{archive}` → starts `scripts/restore.sh --yes` (UI shows its own confirm first) |
| `/api/prereqs` | POST | runs `scripts/prerequisites.sh` as a job |
| `/api/job?since=n` | GET | job status + log slice since line n (client polls ~1 s) |
| `/api/job/cancel` | POST | SIGTERM (SIGKILL after 10 s) — scripts clean their staging via traps |

Single concurrent job; logs tee'd to `logs/<ts>-<type>.log`.

## UI shape

Two hero buttons (BACKUP / RESTORE) → modal dialogs with the embedded explorer + options
(compression level select defaulting to 5, node-dist and logs toggles). Live log pane with status
pill + cancel. System panel with detected versions/sizes and a prerequisites hint when 7zz is
missing. Jobs disable both buttons while running.

## Testability

`tests/webapp/server.test.js` (node:test) spawns the real server with `OBD_*` sandbox env so the
backup job runs against fixture trees; covers static serving, system info, browse modes, path
safety, archive-info, a full backup job through the API, and cancel semantics.

Related: [[architecture/backup-flow]], [[architecture/restore-flow]], [[runbooks/fresh-os-reload]].
