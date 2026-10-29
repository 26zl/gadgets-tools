# AGENTS.md — AI agent guide for gadgets-tools

Vendor-neutral instructions for AI coding agents (Claude Code, Codex, Cursor,
Gemini CLI, Copilot, and others) working in this repository. Client-specific files
may import this one; keep shared rules here.

## What this repo is

A personal collection of pentest-gadget tooling, one folder per device. It mixes
first-party code with third-party Git submodules. See `README.md` for the layout.

## Hard boundaries

- **Do not touch `flipper/Momentum-Firmware`.** Its own `AGENTS.md` prohibits all
  AI-generated contributions and instructs assistants to stop. Do not read it for
  changes, modify it, or review it; leave its submodule pin to Dependabot.
- **Do not modify third-party submodules to "fix" them here.** `flipper/GhostESP`,
  `flipper/ESP32Marauder`, `m5stickc-plus2/ir`, `m5stickc-plus2/evil-portal`, and
  `t-dongle-s3/payloads` are upstreams — send fixes upstream, then bump the pin.
- **First-party submodules** (`galaxy-s10-nethunter/netsec-auditor`,
  `galaxy-s10-nethunter/cybersec-toolkit`) are versioned in their own repositories:
  land the change there and release it, then bump the pin here. **Never pin the
  parent to a commit that is not pushed to the submodule's remote.**
- **Authorized use only.** Everything here is for security testing on devices and
  networks the operator owns or is explicitly permitted to assess.
- **No secrets** in commits or output. **No AI attribution trailers** in commit
  messages or pull requests — match the existing clean history.
- **Hardware actions are destructive.** Never flash a device or run on-device
  provisioning without explicit, per-device confirmation from the operator.

## First-party layout

- `flipper/flipper-feberis/` — Feberis Pro ESP32 firmware (PlatformIO) + `geotag`
- `galaxy-s10-nethunter/scripts/` — Android / Kali provisioning scripts
- `m5stickc-plus2/flash.sh`, `t-dongle-s3/flash.sh` — flashing helpers
- `.github/` — CI and templates

## Build / test / lint (mirrors `.github/workflows/ci.yml`)

```sh
cd flipper/flipper-feberis
python3 -m unittest discover -v
c++ -std=c++17 -O2 tests/date_math_test.cpp -o /tmp/dt && /tmp/dt
c++ -std=c++17 -O2 tests/track_test.cpp     -o /tmp/tk && /tmp/tk
c++ -std=c++17 -O2 tests/format_test.cpp    -o /tmp/fmt && /tmp/fmt
pio run
cd ../..
python3 -m unittest discover -s tests -v
python3 -m unittest discover -s galaxy-s10-nethunter/tests -v
shellcheck -S warning galaxy-s10-nethunter/scripts/*.sh m5stickc-plus2/flash.sh t-dongle-s3/flash.sh
```

## Style

- Shell: 2-space indent, `set -euo pipefail`, must pass `shellcheck -S warning`.
- Python: 4-space indent, clean under `ruff`.
- C/C++: 2-space indent.
- Commits: short, imperative, lower-case subject; no AI attribution trailers.

## Submodules

Initialise with `git submodule update --init` — **not** `--recursive`; the
`flipper/` firmware submodules are large with deep nested libs, so init those
individually only when building them.
