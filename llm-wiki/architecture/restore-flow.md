# architecture/restore-flow

Purpose: how restore.sh rebuilds a machine from a kit — order, safety, and verification.

## Order (matters)

1. **Resolve 7zz**: `--7zz` → `OBD_KIT_7ZZ` → `bin/7zz-<arch>`/`bin/7zz` → PATH. Extract the
   archive to a temp dir; dequarantine; `source manifest.env`; validate required keys; warn on
   arch mismatch (an arm64 kit will not run on Intel).
2. **Quit Ollama** (real mode only; skipped in `OBD_DEST_PREFIX` sandboxes and `--no-quit`).
3. **Ollama app**: existing bundle *renamed* to `<path>.pre-restore-<ts>` (or removed with
   `--purge-existing`) — never silently deleted. If the rename is refused (App Management TCC),
   the error prints exact manual steps. Then `ditto` the bundle into place.
4. **Data homes**: `~/.ollama`, `~/.pi` (same rename-aside + `ditto`), then recreate the Pi
   launcher symlink (`../../.pi/agent/bin/pi`, relative, as originally installed).
   3b. **Claude Code**: `~/.local/share/claude` + `~/.claude` + launcher — the recorded symlink
       target is absolute, so restore remaps any `CLAUDE_SHARE_PATH` prefix through the
       destination mapping (no-op in real mode; keeps sandbox tests coherent).
   3c. **OpenCode**: `~/.opencode` tree.
   3d. **Shell rcs**: for each name in `SHELL_RCS`, restore into `$HOME` — if a file already
       exists there, the kit's copy is written as `<name>.obd-backup` and the user is told to
       merge PATH lines (never clobber).
5. **App-support db** → `~/Library/Application Support/Ollama`.
6. **Node**: if the kit has the brew chain → copy Cellars under `BREW_PREFIX`, recreate
   `opt/<formula>` relative symlinks from `OPT_*` manifest keys, recreate bin entries from
   `brew/bin-entries.txt`. Else, if `node-dist/` exists → install to `/usr/local/lib/obd-node-v<ver>`
   + `/usr/local/bin/node`. Else warn (Pi will be broken until Node exists).
7. **Ollama CLI symlink** → `/usr/local/bin/ollama` (elevation: direct attempt →
   `osascript … with administrator privileges` GUI prompt → manual instruction).
8. **Start + health check** (real mode): `open -a Ollama`, poll `127.0.0.1:11434/api/version` 60 s.
9. **Verify**: runs `restore-kit/verify.sh` with mapped `OBD_*` env + the kit manifest; compares
   model count and versions; nonzero exit fails the restore (exit 4) with the check table shown.

## Safety properties

- Rename-aside (never delete) unless `--purge-existing`; aside copies are left for the user to inspect.
- `--yes` (web app always passes it after its own confirm dialog) skips the interactive prompt.
- All temporary state lives in one `mktemp -d` with EXIT trap cleanup.

## Known manual follow-ups (documented, not automatable)

- Re-enable Ollama "Start at Login" (Login Items are re-registered by the app, not the filesystem).
- If node was restored via the fallback runtime, PATH may need `/usr/local/bin` (normally present).

Related: [[architecture/backup-archive-layout]], [[runbooks/offline-restore]], [[components/ollama]].
