# runbooks/devcontainer-restore

Purpose: give a Linux devcontainer the ollama CLI + harnesses (pi, claude, opencode) wired to
the Mac host's Ollama server — fully offline on the container side.

## One-time (source Mac, online)

1. Full backup as usual → produces `<name>.7z` **and** `<name>-devcontainer.tar.gz`.
   (First backup downloads the Linux payloads, ~3 GB, then caches them in `cache/devcontainer/`.)
2. Copy both files into the container (mounted volume / docker cp).

## In the devcontainer (offline)

```bash
tar -xzf <name>-devcontainer.tar.gz
cd obd-devcontainer
./restore-devcontainer.sh --archive /kit/<name>.7z [--ollama-host http://host.docker.internal:11434] --yes
```

Then:

```bash
ollama list          # shows the HOST's models (they live on the Mac)
ollama launch pi     # Pi wired to the host server
ollama launch claude # Claude Code wired to the host server
```

## Host prerequisite

Expose Ollama to the network (app settings, or `OLLAMA_HOST=0.0.0.0`); otherwise the restore's
reachability probe shows `~` and `ollama list` from the container fails with connection refused.

## What gets installed in the container

ollama CLI, Node (+npm/npx/corepack), pi (+`~/.pi`), claude (+`~/.claude`),
opencode (+config/sessions/state), PATH + `OLLAMA_HOST` in `.bashrc`/`.zshrc`.
**No models, no `~/.ollama`** — models stay on the host.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ollama list` → connection refused | host Ollama not exposed to network (see prerequisite) |
| `host.docker.internal` unresolvable (plain docker, not Docker Desktop) | use `--ollama-host http://172.17.0.1:11434` (docker bridge) or `--network host` |
| exec format error | container arch ≠ payload arch (kit carries both amd64+arm64; check `uname -m`) |
| Alpine container | payloads are glibc — use a Debian/Ubuntu image ([[architecture/devcontainer-kit]]) |

Related: [[architecture/devcontainer-kit]], [[runbooks/fresh-os-reload]], [[reference/paths]].
