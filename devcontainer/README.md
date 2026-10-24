# Example validation devcontainer

This is the "example devcontainer of the specific type" used to **validate** a devcontainer kit
before you depend on it. It is NOT needed to build the kit — `scripts/capture-devcontainer.sh`
downloads the Linux payloads on the Mac host at backup time. This container is where you
*rehearse* the restore.

The kit's payloads are **glibc Linux builds** — use a Debian/Ubuntu-style image (this one is
`debian:bookworm`). Alpine (musl) is not supported by these payloads.

## Rehearse a restore (fully offline inside the container)

```bash
# from the folder holding <name>.7z and <name>-devcontainer.tar.gz:
docker run --rm -it \
  -v "$PWD":/kit \
  debian:bookworm bash -c '
    apt-get update -qq && apt-get install -y -qq curl xz-utils >/dev/null   # rehearsal only; restore itself is offline-capable
    tar -xzf /kit/<name>-devcontainer.tar.gz -C /tmp
    cd /tmp/obd-devcontainer
    ./restore-devcontainer.sh --archive /kit/<name>.7z --ollama-host http://host.docker.internal:11434 --yes
  '
```

Notes:
- `apt-get` above is only to make the *rehearsal* container curl-capable; the kit's own restore
  path needs nothing but the tar+shell that every image has (the kit bundles its own 7zz and
  binaries). If your base image already has curl, drop the apt line entirely.
- The restore reaches the **host's** Ollama at `http://host.docker.internal:11434` — expose
  Ollama on the Mac first (app settings → "Expose Ollama to the network").
- Success = verification table all-✓ (host reachability may show `~` if the host isn't exposed yet).

## VS Code devcontainer

`.devcontainer/devcontainer.json` in this folder opens the same image in VS Code if you prefer a
full devcontainer session: after restore, run `ollama list`, then `ollama launch pi` or
`ollama launch claude`.
