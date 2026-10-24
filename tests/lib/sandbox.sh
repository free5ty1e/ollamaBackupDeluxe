#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal $HOME in fixture rc is intentional
# sandbox.sh — build a miniature replica of the real inference layout for e2e
# tests. All paths are tiny; the "binaries" are sh scripts. Used with the
# OBD_* env overrides (see scripts/common.sh) so backup/restore never touch
# the real machine.

# make_fixture_tree <root> — echoes nothing; fails on error.
# Layout produced:
#   <root>/Applications/Ollama.app/Contents/{MacOS/Ollama, Resources/ollama, Resources/lib.dylib}
#   <root>/fake-home/.ollama/{config.json,id_ed25519,id_ed25519.pub,onboarding-v1.completed,
#            logs/server.log, models/{blobs,manifests,manifests-v2}}
#   <root>/fake-home/.pi/agent/{bin/pi, install/{current-version,releases/1.2.3,staging/junk},
#            auth.json,settings.json,models.json,models-store.json,sessions/,npm/}
#   <root>/fake-home/.local/bin/pi -> ../../.pi/agent/bin/pi   (NOT created; restore recreates it)
#   <root>/fake-home/Library/Application Support/Ollama/db.sqlite
#   <root>/brew/{Cellar/{node/9.9.9,icu4c@9/9},opt/{node,icu4c@9},bin/{node,npm}}
make_fixture_tree() {
  mkdir -p "$1" || return 1
  local root; root="$(cd "$1" && pwd -P)"; rm -rf "$root"; mkdir -p "$root" || return 1

  # --- Ollama.app ---
  local app="$root/Applications/Ollama.app/Contents"
  mkdir -p "$app/MacOS" "$app/Resources"
  printf '#!/bin/sh\nexit 0\n' > "$app/MacOS/Ollama"; chmod +x "$app/MacOS/Ollama"
  cat > "$app/Resources/ollama" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then echo 'ollama version is 0.99.0'; fi
exit 0
EOF
  chmod +x "$app/Resources/ollama"
  echo "pretend dylib" > "$app/Resources/libggml.dylib"

  # --- ~/.ollama ---
  local oh="$root/fake-home/.ollama"
  mkdir -p "$oh/logs" "$oh/cache" "$oh/models/blobs" \
           "$oh/models/manifests/registry.ollama.ai/library/testmodel" \
           "$oh/models/manifests/registry.ollama.ai/user42/custom" \
           "$oh/models/manifests-v2/ollama.com/library/other"
  echo '{}' > "$oh/config.json"
  echo "fake-key" > "$oh/id_ed25519"; echo "fake-pub" > "$oh/id_ed25519.pub"
  touch "$oh/onboarding-v1.completed"
  echo "log line" > "$oh/logs/server.log"
  echo "cache-entry" > "$oh/cache/blob.tmp"
  # blobs are content-addressed: name them by the sha256 of their content so the
  # validator's blob-verification check works against fixtures too
  h1="$(printf 'weights' | shasum -a 256 | awk '{print $1}')"
  h2="$(printf 'weights2' | shasum -a 256 | awk '{print $1}')"
  printf 'weights' > "$oh/models/blobs/sha256-$h1"
  printf 'weights2' > "$oh/models/blobs/sha256-$h2"
  echo '{}' > "$oh/models/manifests/registry.ollama.ai/library/testmodel/1.0"
  echo '{}' > "$oh/models/manifests/registry.ollama.ai/user42/custom/3.1"
  echo '{}' > "$oh/models/manifests-v2/ollama.com/library/other/2.0"

  # --- ~/.pi ---
  local pi="$root/fake-home/.pi/agent"
  mkdir -p "$pi/bin" "$pi/install/releases/1.2.3/node_modules/.bin" "$pi/install/staging" \
           "$pi/sessions" "$pi/npm"
  cat > "$pi/bin/pi" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then echo '1.2.3'; fi
exit 0
EOF
  chmod +x "$pi/bin/pi"
  echo "1.2.3" > "$pi/install/current-version"
  echo '{"pi":"stub"}' > "$pi/install/releases/1.2.3/node_modules/.bin/pi"
  echo "partial download" > "$pi/install/staging/junk.part"
  echo '{"tokens":{}}' > "$pi/auth.json"
  echo '{}' > "$pi/settings.json"; echo '{}' > "$pi/models.json"; echo '{}' > "$pi/models-store.json"
  echo '{}' > "$pi/sessions/s1.json"; echo 'pkg' > "$pi/npm/thing"

  # --- Claude Code (native install layout: absolute launcher symlink) ---
  local cl="$root/fake-home/.local/share/claude"
  mkdir -p "$cl/versions" "$root/fake-home/.claude/sessions" "$root/fake-home/.claude/backups" "$root/fake-home/.claude/cache"
  cat > "$cl/versions/2.1.251" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then echo '2.1.251 (Claude Code)'; fi
exit 0
EOF
  chmod +x "$cl/versions/2.1.251"
  mkdir -p "$root/fake-home/.local/bin"
  ln -s "$cl/versions/2.1.251" "$root/fake-home/.local/bin/claude"
  echo '{}' > "$root/fake-home/.claude/settings.json"
  echo '{}' > "$root/fake-home/.claude/sessions/s1.json"
  echo 'backup' > "$root/fake-home/.claude/backups/b1.json"
  echo 'cache' > "$root/fake-home/.claude/cache/c.tmp"

  # --- OpenCode (self-contained binary + post-first-run data dirs) ---
  mkdir -p "$root/fake-home/.opencode/bin" "$root/fake-home/.opencode/node_modules/@opencode-ai/plugin"
  cat > "$root/fake-home/.opencode/bin/opencode" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then echo '1.19.0'; fi
exit 0
EOF
  chmod +x "$root/fake-home/.opencode/bin/opencode"
  echo '{}' > "$root/fake-home/.opencode/package.json"
  echo '{"name":"plugin"}' > "$root/fake-home/.opencode/node_modules/@opencode-ai/plugin/index.js"

  mkdir -p "$root/fake-home/.config/opencode/node_modules"            "$root/fake-home/.local/share/opencode/log"            "$root/fake-home/.local/state/opencode/locks"
  echo '{}' > "$root/fake-home/.config/opencode/opencode.jsonc"
  echo '{"name":"x"}' > "$root/fake-home/.config/opencode/node_modules/pkg.js"
  echo 'sqlite' > "$root/fake-home/.local/share/opencode/opencode.db"
  echo 'log' > "$root/fake-home/.local/share/opencode/log/opencode.log"
  echo '{"model":"x"}' > "$root/fake-home/.local/state/opencode/model.json"
  echo 'q?' > "$root/fake-home/.local/state/opencode/prompt-history.jsonl"

  # other app in ~/.config that must NOT be captured
  mkdir -p "$root/fake-home/.config/filezilla"; echo 'unrelated' > "$root/fake-home/.config/filezilla/fz.txt"

  # --- shell rc (PATH wiring) ---
  printf '# fixture rc\nexport PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"\n' > "$root/fake-home/.zshrc"

  # --- Application Support ---
  mkdir -p "$root/fake-home/Library/Application Support/Ollama"
  echo "sqlite" > "$root/fake-home/Library/Application Support/Ollama/db.sqlite"

  # --- fake brew with node + icu4c@9 ---
  local bp="$root/brew"
  mkdir -p "$bp/Cellar/node/9.9.9/bin" "$bp/Cellar/node/9.9.9/lib/node_modules/npm/bin" \
           "$bp/Cellar/icu4c@9/9/lib" "$bp/opt" "$bp/bin" "$bp/lib/node_modules/npm/bin"
  cat > "$bp/Cellar/node/9.9.9/bin/node" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then echo 'v9.9.9'; fi
exit 0
EOF
  chmod +x "$bp/Cellar/node/9.9.9/bin/node"
  echo '{"name":"npm"}' > "$bp/Cellar/node/9.9.9/lib/node_modules/npm/bin/npm-cli.js"
  cat > "$bp/lib/node_modules/npm/bin/npm-cli.js" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then echo '11.20.0'; fi
exit 0
EOF
  chmod +x "$bp/lib/node_modules/npm/bin/npm-cli.js"
  echo "icu" > "$bp/Cellar/icu4c@9/9/lib/libicuuc.9.dylib"
  ln -s ../Cellar/node/9.9.9 "$bp/opt/node"
  ln -s "../Cellar/icu4c@9/9" "$bp/opt/icu4c@9"
  ln -s ../Cellar/node/9.9.9/bin/node "$bp/bin/node"
  ln -s ../lib/node_modules/npm/bin/npm-cli.js "$bp/bin/npm"

  # --- brew shim so tests are deterministic regardless of the real brew state ---
  mkdir -p "$root/shims"
  cat > "$root/shims/brew" <<'EOF'
#!/bin/sh
# stub brew: `brew deps <formula>` -> the fixture's dep formulae, one per line
if [ "$1" = "deps" ]; then echo "icu4c@9"; fi
exit 0
EOF
  chmod +x "$root/shims/brew"

  return 0
}

# sandbox_env <root> — export the OBD_* overrides pointing into the fixture
sandbox_env() {
  local root; root="$(cd "$1" 2>/dev/null && pwd -P)"; root="${root:-$1}"
  export OBD_HOME="$root/fake-home"
  export OBD_OLLAMA_APP="$root/Applications/Ollama.app"
  export OBD_OLLAMA_CLI="$root/usr-local/bin/ollama"
  export OBD_OLLAMA_HOME="$OBD_HOME/.ollama"
  export OBD_OLLAMA_APP_SUPPORT="$OBD_HOME/Library/Application Support/Ollama"
  export OBD_PI_HOME="$OBD_HOME/.pi"
  export OBD_PI_LAUNCHER="$OBD_HOME/.local/bin/pi"
  export OBD_CLAUDE_HOME="$OBD_HOME/.claude"
  export OBD_CLAUDE_SHARE="$OBD_HOME/.local/share/claude"
  export OBD_CLAUDE_LAUNCHER="$OBD_HOME/.local/bin/claude"
  export OBD_OPENCODE_HOME="$OBD_HOME/.opencode"
  export OBD_OPENCODE_CONFIG="$OBD_HOME/.config/opencode"
  export OBD_OPENCODE_SHARE="$OBD_HOME/.local/share/opencode"
  export OBD_OPENCODE_STATE="$OBD_HOME/.local/state/opencode"
  export OBD_SKIP_DC=1   # standard suites never download linux payloads
  export OBD_BREW_PREFIX="$root/brew"
  export OBD_NODE_BIN="$root/brew/Cellar/node/9.9.9/bin/node"
  case ":$PATH:" in
    *":$root/shims:"*) ;;
    *) export PATH="$root/shims:$PATH" ;;
  esac
}
