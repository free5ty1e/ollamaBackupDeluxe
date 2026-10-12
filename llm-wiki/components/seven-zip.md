# components/seven-zip

Purpose: how 7zz is obtained, what this build supports, and the bash traps around it.

## Acquisition (prerequisites.sh → `bin/7zz`, gitignored)

Order: already in `bin/` → system `7zz`/`7zzs` (copied into bin so kits embed it) →
`brew install sevenzip` → direct download from `github.com/ip7z/7zip/releases`.
Downloaded binaries are dequarantined (`xattr -dr com.apple.quarantine`).

Learned 2026-10-12: the macOS asset is **arch-agnostic** — `7z<ver>-mac.tar.xz` contains a
universal binary; there is no `-mac-arm64`/`-mac-x64` asset. The release bundle therefore ships
one universal `bin/7zz`.

## Switch behavior (7-Zip 26.04 "z" build, macOS)

- **No `-l` switch.** Default `a` behavior **dereferences symlinks** — archive contains real
  file content under staging-relative paths (`-snl` opts INTO storing links as links). This is
  the foundation of the no-duplication staging design ([[architecture/backup-flow]]).
- `-so` + `e` extracts a single archived file to stdout — used to read `manifest.env` out of an
  archive (`7zz e -y -bso0 -ba -so <archive> manifest.env`).
- `-bso0 -bse0` silences; `-bsp1` emits progress (carriage-return separated — sanitize with
  `tr '\r' '\n'` when capturing).

## bash traps (all hit and fixed 2026-10-12 — see [[reference/troubleshooting]])

- `7zz … | head -1` under `pipefail`: head exits early → 7zz SIGPIPE (rc 141) → pipeline fails
  even when the wanted line was read. Fix: capture full output (it's tiny) then filter.
- `curl … | grep -m1` — same early-exit SIGPIPE, curl rc 23.
- 7zz's first output line is **blank**; the version banner is a later line.

## Kit embedding

Every kit carries `restore-kit/7zz` so the restore side never needs to install anything
([[architecture/backup-archive-layout]], [[runbooks/offline-restore]]).
