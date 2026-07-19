#!/usr/bin/env bash
# Flash Bruce onto an M5StickC PLUS2 (plug in via USB): ./flash.sh [port]
set -euo pipefail

REPO="BruceDevices/firmware"
ASSET="Bruce-m5stack-cplus2.bin"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

echo "==> downloading Bruce ($ASSET, latest release)"
gh release download --repo "$REPO" --pattern "$ASSET" --dir "$W"

PORT="${1:-$(ls /dev/cu.usbserial* /dev/cu.wchusbserial* /dev/cu.SLAB_USBtoUART* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | head -1 || true)}"
if [ -z "$PORT" ]; then
  echo "!! No serial port found. Plug in the StickC and pass the port:"
  echo "   ./flash.sh /dev/cu.usbserial-XXXX"
  exit 1
fi

if command -v esptool.py >/dev/null 2>&1; then ESPTOOL=(esptool.py)
elif python3 -c 'import esptool' >/dev/null 2>&1; then ESPTOOL=(python3 -m esptool)
else echo "!! esptool not found — install: pip install esptool"; exit 1; fi

echo "==> flashing on $PORT (esp32, merged image @ 0x0)"
"${ESPTOOL[@]}" --chip esp32 --port "$PORT" --baud 921600 write_flash 0x0 "$W/$ASSET"

echo "==> done! The StickC reboots into Bruce's on-screen menu."
echo "    (If it hangs, press the reset/power button.)"
