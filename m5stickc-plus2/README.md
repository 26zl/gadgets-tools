# m5stickc-plus2

Setup for the **M5StickC PLUS2** (ESP32) running [Bruce](https://github.com/BruceDevices/firmware) — a Flipper-like offensive ESP32 multi-tool with an on-device GUI.

> **Authorized use only.** Own or explicitly permitted targets.

## What works on this device
The StickC PLUS2 is a classic ESP32 with WiFi/BLE + an IR LED — but no SubGHz/RFID/NFC radios and no native USB.

| Feature | On StickC PLUS2 |
| --- | --- |
| WiFi (deauth, evil portal, beacon spam, scan) | ✅ |
| BLE (spam, scan) | ✅ |
| IR (TV-B-Gone, remotes) | ✅ |
| SubGHz / RFID / NFC | ❌ no hardware |
| BadUSB / DuckyScript | ❌ no USB-HID (that's the T-Dongle's job) |

## Flash
```bash
pip install esptool
./flash.sh                   # or: ./flash.sh /dev/cu.usbserial-XXXX
```
Or the no-tools web flasher: [bruce.computer/flasher](https://bruce.computer/flasher) → connect → pick **M5StickC PLUS2** → Flash. Bruce ships as one merged `.bin` flashed at `0x0`. `flash.sh` works on macOS/Linux; on **Windows/WSL** the web flasher is easiest (no USB passthrough), or attach the StickC with [usbipd-win](https://github.com/dorssel/usbipd-win).

## IR codes — [`ir/`](ir/)
Universal remote database ([Lucaslhm/Flipper-IRDB](https://github.com/Lucaslhm/Flipper-IRDB), ~8900 `.ir` files) — Bruce reads Flipper `.ir` format directly.
```bash
git submodule update --init m5stickc-plus2/ir   # pinned commit (add --remote to update)
```
The StickC has no SD slot, so upload the `.ir` files you want via Bruce's **WebUI** (into LittleFS), then send from the IR menu.

## Evil Portal templates — [`evil-portal/`](evil-portal/)
Captive-portal HTML for Bruce ([Batcherss/evil-portal-html](https://github.com/Batcherss/evil-portal-html)) — use the [`Bruce/`](evil-portal/Bruce/) folder.
```bash
git submodule update --init m5stickc-plus2/evil-portal   # pinned commit (add --remote to update)
```
Load an HTML file into Bruce's **Evil Portal** feature. **Authorized security tests only.**

## Notes
- The StickC uses a USB-serial chip (`/dev/cu.usbserial*` on macOS, `/dev/ttyUSB*` on Linux).
- After flashing it boots into Bruce's menu — navigate with the two front buttons.

Full docs: [Bruce firmware](https://github.com/BruceDevices/firmware) · [wiki](https://github.com/BruceDevices/firmware/wiki).
