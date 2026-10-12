# reference/troubleshooting

Purpose: every failure mode actually hit while building/running this tool, and the fix.

## bash + `set -euo pipefail` traps (all bit us on 2026-10-12)

| Symptom | Cause | Fix |
|---|---|---|
| `MAC_ARCH…: unbound variable` | `"$VAR…"` — a trailing `…` (U+2026) becomes part of the variable name | `${VAR}…` |
| pipeline exits 23 (curl) or 141 | `curl … | grep -m1` / `cmd | head -1` under `pipefail`: the reader exits early, writer gets SIGPIPE | capture full output first, then filter (`out="$(cmd … || true)"`) |
| script dies silently after a helper | `[[ cond ]] && cmd` as the last statement of a loop/function returns 1 when cond is false | `if cond; then cmd; fi` |
| verify stops after first ✓ | `((PASS++))` evaluates to 0 → exit status 1 → set -e | `PASS=$((PASS+1))` |
| every path "invalid" | `[[ "$p" != *$'\0'* ]]` — `$'\0'` is an empty string in bash, so `*""*` matches everything | drop the NUL check (bash strings can't contain NUL) |
| `local` outside function | top-level `local` in an `if` body | remove it |

## 7-Zip specifics

- No `-l` switch in the 26.04 macOS build; default `a` already dereferences symlinks
  ([[components/seven-zip]]). `-snl` opts into storing links as links — do not pass it.
- macOS release asset is `7z<ver>-mac.tar.xz` (universal binary); arch-suffixed URLs 404.
- First line of `7zz` output is blank — don't parse line 1.

## macOS specifics

- **App Management (TCC)** can refuse renaming/deleting a signed bundle in `/Applications`
  (Sequoia+). Restore moves the old bundle aside first; if refused it prints drag-to-Trash
  instructions. Fresh-OS restores are unaffected (target doesn't exist).
- `/tmp` is a symlink to `/private/tmp` — `readlink -f` returns `/private/tmp/...`; anything
  comparing resolved paths to unresolved prefixes must normalize (`pwd -P`) first. Bit the
  sandbox fixture (brew-mode detection) and fixed in `tests/lib/sandbox.sh`.
- `/usr/local/bin` is root-owned: expect the one-time admin prompt (osascript) when the CLI
  symlink is recreated.
- Ollama's "Start at Login" is a Login Item — not captured by any filesystem backup; must be
  re-enabled manually after restore.

## Design-level gotchas

- `brew deps node` on the host returns the HOST's dep set (e.g. `icu4c@78`); tests stub `brew`
  on PATH so fixtures are deterministic ([[reference/paths]]).
- Brew bin symlinks can be relative (`../lib/node_modules/...`) — textual matching misses them;
  match on `readlink -f` resolved targets.
- Node dist: prefer `.tar.xz` (29 MB) over `.tar.gz` (56 MB) — release zip shrank 114→62 MB;
  macOS `tar` reads xz natively.
- The web app's `du -sk` on 61 GB is slow — sizes are cached 60 s in `/api/system`.

Related: [[components/seven-zip]], [[architecture/restore-flow]], [[runbooks/offline-restore]].
