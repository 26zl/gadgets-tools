# Contributing

This is a personal collection of pentest-gadget tooling. Contributions and bug
reports for the **first-party** parts are welcome; upstream firmware and libraries
pulled in as submodules should be contributed to their own projects.

## First-party vs. submodules

First-party — change these here:

- `flipper/flipper-feberis/` — Feberis Pro firmware and the `geotag` tool
- `galaxy-s10-nethunter/scripts/` — provisioning / reinstall scripts
- `m5stickc-plus2/flash.sh`, `t-dongle-s3/flash.sh` — flashing helpers
- `.github/` and the root documentation

Submodules — contribute upstream, not here:

- `flipper/Momentum-Firmware` — its `AGENTS.md` **prohibits AI-generated
  contributions**; do not modify that tree and disable AI assistants for it.
- `flipper/GhostESP`, `flipper/ESP32Marauder`, `m5stickc-plus2/ir`,
  `m5stickc-plus2/evil-portal`, `t-dongle-s3/payloads` — third-party upstreams.
- `galaxy-s10-nethunter/netsec-auditor`, `galaxy-s10-nethunter/cybersec-toolkit` —
  first-party but versioned in their own repositories: land the change there, cut a
  release, then bump the submodule pin here.

## Getting set up

```sh
git clone https://github.com/26zl/gadgets-tools.git
cd gadgets-tools
git submodule update --init          # NOT --recursive — see the README
```

Toolchain used by CI: Python 3.12+, PlatformIO ~6.1, a C++17 compiler, ShellCheck,
and Node (for markdownlint via `npx`).

## Checks to run before a pull request

These mirror `.github/workflows/ci.yml`:

```sh
# Feberis Python + native C++ tests + firmware build
cd flipper/flipper-feberis
python3 -m unittest discover -v
c++ -std=c++17 -O2 tests/date_math_test.cpp -o /tmp/dt && /tmp/dt
c++ -std=c++17 -O2 tests/track_test.cpp     -o /tmp/tk && /tmp/tk
c++ -std=c++17 -O2 tests/format_test.cpp    -o /tmp/fmt && /tmp/fmt
pio run
cd ../..

# Script safety tests
python3 -m unittest discover -s tests -v
python3 -m unittest discover -s galaxy-s10-nethunter/tests -v

# Lint
shellcheck -S warning galaxy-s10-nethunter/scripts/*.sh m5stickc-plus2/flash.sh t-dongle-s3/flash.sh
```

## Style

- Shell: 2-space indent, `set -euo pipefail`, must pass `shellcheck -S warning`.
- Python: 4-space indent, keep it clean under `ruff`.
- C/C++: 2-space indent.
- Commit messages: short, imperative, lower-case subject (see `git log`); no AI
  attribution trailers — match the existing history.
- Never commit a submodule pin that points at an unpushed commit, and don't bump a
  submodule past what you have verified.
- No secrets, credentials, or captured data in commits.

## Authorized use

Only for devices and networks you own or are explicitly permitted to assess. Laws on
RF capture, wardriving, and USB/HID vary by country.
