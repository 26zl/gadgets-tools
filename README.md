# gadgets-tools

[![ci](https://github.com/26zl/gadgets-tools/actions/workflows/ci.yml/badge.svg)](https://github.com/26zl/gadgets-tools/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Tools and firmware for various Flipper Zero, ESP32, and phone pentest gadgets — one folder per device.

> **Authorized use only.** Everything here is for security testing on devices and networks you
> own or are explicitly permitted to assess. RF-capture, wardriving, and USB/HID laws vary by country.

| Folder | Device | What's here |
| --- | --- | --- |
| [`flipper/`](flipper/) | Flipper Zero | Feberis Pro recon firmware + `geotag` ([`flipper-feberis/`](flipper/flipper-feberis/)) · WiFi Dev Board tools ([`flipper-wifi-devboard/`](flipper/flipper-wifi-devboard/), WIP) · upstream ESP32 firmwares as submodules (Momentum, GhostESP, ESP32Marauder) |
| [`t-dongle-s3/`](t-dongle-s3/) | LilyGo T-Dongle-S3 | USBArmyKnife (USB pentest implant) + payload library |
| [`m5stickc-plus2/`](m5stickc-plus2/) | M5StickC PLUS2 | Bruce (Flipper-like ESP32 multi-tool) |
| [`galaxy-s10-nethunter/`](galaxy-s10-nethunter/) | Samsung Galaxy S10 (SM-G973F) | Kali NetHunter reinstall + provisioning scripts (`scripts/`), plus the `netsec-auditor` and `cybersec-toolkit` submodules (run on the phone) |

Each folder is self-contained — see its own README. After cloning, `git submodule update --init` pulls the tool submodules. **Don't add `--recursive`** — the `flipper/` firmware submodules (Momentum, GhostESP, ESP32Marauder) are large (~1.5 GB) with deep nested libs that only matter for WiFi-Dev-Board builds; init those individually when you build them.

MIT licensed — see [LICENSE](LICENSE).
