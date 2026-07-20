#!/usr/bin/env bash
# On-device AI for the Galaxy S10 NetHunter chroot: Claude Code (cloud CLI) + a
# local LLM (llama.cpp) — both pure on-demand (nothing runs in the background;
# RAM is freed the moment they exit).
#
# Run INSIDE the Kali chroot as root (phone-side), over ssh-setup.sh's channel:
#   ssh s10 'bash -s' < scripts/ai-setup.sh
# ...or paste it in the NetHunter (Kali) terminal. Needs internet in the chroot.
# Idempotent — safe to re-run (skips an existing build / already-downloaded models).
#
# Installs:
#   claude          Claude Code CLI — Anthropic API client (full model, needs internet
#                   + login; run `claude` once to authenticate). The tool for real work.
#   llm  "..."      local Llama-3.2-3B-Instruct Q4_K_M  (~3.7 tok/s, better quality)
#   llmf "..."      local Llama-3.2-1B-Instruct Q4_K_M  (~8 tok/s, fast; weak — quick/offline)
#                   no args => interactive chat (/exit to quit)
#
# Two Exynos-9820-specific lessons are baked in (see README "On-device AI"):
#   1. dotprod must be FORCED at build time — GCC's -march=native does NOT enable it
#      on Samsung's custom M4 core (falls back to generic armv8-a, ~2 tok/s), so we
#      compile explicitly for armv8.2-a+dotprod+fp16.
#   2. The 2 M4 (Mongoose) cores (cpu 6-7) throttle erratically and stall llama.cpp's
#      per-token thread barrier — pinning to cores 0-5 (A55+A75) ~doubles throughput.
set -uo pipefail

command -v apt-get >/dev/null 2>&1 || { echo "Run this INSIDE the Kali chroot (no apt-get here)."; exit 1; }
[ "$(id -u)" = 0 ] || { echo "Run as root inside the chroot."; exit 1; }
step(){ printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

LLAMA_SRC=/opt/llama.cpp
MODELS=/opt/models
M3="$MODELS/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
M1="$MODELS/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
M3_URL="https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
M1_URL="https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf"

step "1/6  Claude Code CLI"
if command -v claude >/dev/null 2>&1; then
  echo "    already installed: $(claude --version 2>/dev/null | head -1)"
else
  curl -fsSL https://claude.ai/install.sh | bash || echo "    (claude install returned nonzero — check network)"
fi
# Symlink so `claude` resolves in ANY shell, not just an interactive zsh that sources ~/.zshrc.
[ -x /root/.local/bin/claude ] && ln -sf /root/.local/bin/claude /usr/local/bin/claude
command -v claude >/dev/null 2>&1 && echo "    claude -> $(command -v claude)"

step "2/6  Build dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends build-essential cmake git curl libcurl4-openssl-dev 2>&1 | tail -3

step "3/6  Build llama.cpp with dotprod forced (see header note #1)"
[ -d "$LLAMA_SRC/.git" ] || git clone --depth=1 https://github.com/ggml-org/llama.cpp "$LLAMA_SRC"
cd "$LLAMA_SRC" || { echo "cannot enter $LLAMA_SRC"; exit 1; }
if [ ! -x build/bin/llama-cli ]; then
  cmake -B build -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH="armv8.2-a+dotprod+fp16" \
        -DLLAMA_CURL=ON -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >/dev/null
  cmake --build build -j4 --target llama-cli
fi
install -m755 build/bin/llama-cli /usr/local/bin/
echo "    llama-cli -> $(command -v llama-cli)  (arch: $(grep -hoE 'march=armv8[^" ]*' build/compile_commands.json 2>/dev/null | sort -u | head -1))"

step "4/6  Download models (~2.7 GB: 3B + 1B)"
mkdir -p "$MODELS"
for pair in "$M3|$M3_URL" "$M1|$M1_URL"; do
  f="${pair%%|*}"; url="${pair##*|}"
  if [ -s "$f" ]; then
    echo "    have $(basename "$f")"
  else
    echo "    fetching $(basename "$f") ..."
    curl -L --fail --retry 3 -o "$f" "$url" && echo "    -> $(du -h "$f" | cut -f1)" \
      || echo "    !! download failed: $url"
  fi
done

step "5/6  Install llm / llmf wrappers (pinned to cores 0-5 — see header note #2)"
mkwrap(){ # $1 command name  $2 model path
  cat > "/usr/local/bin/$1" <<WRAP
#!/bin/bash
# Local LLM — on-demand. Loads model, answers, EXITS (nothing stays resident).
M=$2
if [ \$# -gt 0 ]; then
  taskset -c 0-5 llama-cli -m "\$M" -t 6 -c 4096 -st --simple-io -p "\$*" </dev/null
else
  taskset -c 0-5 llama-cli -m "\$M" -t 6 -c 4096 -cnv
fi
WRAP
  chmod +x "/usr/local/bin/$1"
}
mkwrap llm  "$M3"
mkwrap llmf "$M1"
echo "    llm (3B), llmf (1B) installed"

step "6/6  Verify"
echo -n "    claude:    "; command -v claude >/dev/null 2>&1 && claude --version 2>/dev/null | head -1 || echo MISSING
echo -n "    llm/llmf:  "; { command -v llm && command -v llmf; } >/dev/null 2>&1 && echo ok || echo MISSING
echo    "    models:    $(ls -1 "$MODELS"/*.gguf 2>/dev/null | wc -l | tr -d ' ') gguf in $MODELS"
echo -n "    llmf live: "; timeout 60 llmf "Reply with exactly: ok" 2>/dev/null | tr -d '\n' | grep -oiE 'ok' | head -1 || echo "(no output)"

cat <<'DONE'

Done — both are on-demand (nothing runs in the background; RAM freed on exit):
  claude               # first run: log in (browser OAuth); needs internet
  llmf "your prompt"   # fast local model (~8 tok/s)
  llm  "your prompt"   # better local model (~3.7 tok/s); no args = chat, /exit to quit
DONE
