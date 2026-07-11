# t-dongle-s3

Setup for the **LilyGo T-Dongle-S3** running [USBArmyKnife](https://github.com/i-am-shodan/USBArmyKnife) — an ESP32-S3 USB pentest tool (BadUSB/HID, network attacks, web-driven payloads).

> **Authorized use only.** Only run payloads against devices you own or are explicitly permitted to test.

The T-Dongle-S3 is USBArmyKnife's **recommended** board — ESP32-S3 with native USB, so it flashes straight over USB (no Flipper bridge).

## 1. Get the firmware
Download **`LILYGO-T-Dongle-S3.Firmware.binaries.zip`** from the [USBArmyKnife releases](https://github.com/i-am-shodan/USBArmyKnife/releases). It contains `bootloader.bin`, `partitions.bin`, `firmware.bin` (ignore `firmware.elf`). You also need `boot_app0.bin` from [arduino-esp32](https://github.com/espressif/arduino-esp32/raw/master/tools/partitions/boot_app0.bin).

## 2. Enter boot mode
**Hold the side button, plug the dongle into USB, wait ~1 s, release.**

## 3. Flash

**Option A — one command (`flash.sh`, needs `esptool` + `gh`):**
```bash
pip install esptool          # if you don't have it
./flash.sh                   # or: ./flash.sh /dev/cu.usbmodemXXXX
```
It downloads the firmware + `boot_app0.bin` and flashes at the ESP32-S3 offsets.

**Option B — no tools (web flasher):**
Open [esp.huhn.me](https://esp.huhn.me/) in Chrome/Edge → Connect → add the files at these offsets → Program:

| File | Offset |
| --- | --- |
| `bootloader.bin` | `0x0` |
| `partitions.bin` | `0x8000` |
| `boot_app0.bin` | `0xE000` |
| `firmware.bin` | `0x10000` |

> Note the **`0x0`** bootloader offset — ESP32-S3 differs from the classic ESP32 (which uses `0x1000`).

## 4. SD card (optional, recommended)
Format a microSD as a **single FAT32 partition** (≤32 GB works best) and insert it after flashing — payloads and captures live there.

## 5. First connect
Unplug/replug. The dongle brings up its own WiFi AP:
- **SSID:** `iPhone14`   **Password:** `password`
- Web UI: **http://4.3.2.1:8080** — write and run DuckyScript payloads here.

Change the SSID/password in the web-UI preferences.

## Payloads
Community DuckyScript payloads live in [`payloads/`](payloads/) — a git submodule of the official [Hak5 library](https://github.com/hak5/usbrubberducky-payloads).

```bash
git submodule update --init --remote t-dongle-s3/payloads   # fetch / pull latest
```
A fresh `git clone` of this repo needs `--recursive`, or run the command above once.

Load a payload's DuckyScript into the USBArmyKnife web UI. **⚠️ Read it first** — some download and run remote code. Authorized targets only.

Full docs: the [USBArmyKnife wiki](https://github.com/i-am-shodan/USBArmyKnife/wiki).
