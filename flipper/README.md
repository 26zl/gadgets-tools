# flipper

Flipper Zero tooling and ESP32-companion firmware. The Flipper itself runs [Momentum](https://momentum-fw.dev/) custom firmware; its ESP32 add-on boards (Feberis Pro, WiFi Dev Board) run one of the firmwares here.

> **Authorized use only.** Everything here is for security testing on devices and networks you own or are explicitly permitted to assess.

## Folders

| Folder | What's here |
| --- | --- |
| [`flipper-feberis/`](flipper-feberis/) | **Feberis Pro** (ESP32 + GPS) recon firmware — live WiFi scan, offline dashboard, WiGLE CSV / GPX export — plus the `geotag` desktop tool |
| [`flipper-wifi-devboard/`](flipper-wifi-devboard/) | Flipper Zero official WiFi Dev Board tools — **not started yet** |

## Vendored firmware (submodules)

Upstream firmware pinned as submodules, for flashing onto the boards. **Large (~1.5 GB total)** and only needed when you actually build/flash — init them individually, and **never `git submodule update --recursive`** (a git 2.55 bug chokes on their nested libs; use `--init`).

| Submodule | What | Upstream |
| --- | --- | --- |
| [`Momentum-Firmware/`](Momentum-Firmware/) | Flipper Zero custom firmware (ships the **ESP Flasher** app used to flash the ESP32 boards) | [Next-Flip/Momentum-Firmware](https://github.com/Next-Flip/Momentum-Firmware) |
| [`GhostESP/`](GhostESP/) | ESP32 offensive multi-tool (WiFi/BLE/GPS) — Sapsan's feature-rich firmware for the Feberis Pro | [GhostESP-Revival/GhostESP](https://github.com/GhostESP-Revival/GhostESP) |
| [`ESP32Marauder/`](ESP32Marauder/) | Classic ESP32 WiFi/BLE tool — the Feberis Pro's stock ESP32 firmware | [justcallmekoko/ESP32Marauder](https://github.com/justcallmekoko/ESP32Marauder) |

How these relate — the Feberis Pro firmware choice (GhostESP / Marauder / the custom `flipper-feberis` build) — is covered in [`flipper-feberis/README.md`](flipper-feberis/README.md).

```bash
git submodule update --init flipper/GhostESP                     # pull one board's firmware
cd flipper/ESP32Marauder && git submodule update --init --jobs 1 # its nested libs, only when building
```

MIT licensed — see [LICENSE](../LICENSE).
