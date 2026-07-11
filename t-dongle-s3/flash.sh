#!/usr/bin/env bash
# Flash USBArmyKnife onto a T-Dongle-S3 in boot mode (hold button, plug in): ./flash.sh [port]
set -euo pipefail

REPO="i-am-shodan/USBArmyKnife"
ASSET="LILYGO-T-Dongle-S3.Firmware.binaries.zip"
BOOT_APP0_URL="https://raw.githubusercontent.com/espressif/arduino-esp32/master/tools/partitions/boot_app0.bin"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

echo "==> downloading firmware ($ASSET)"
gh release download --repo "$REPO" --pattern "$ASSET" --dir "$W"
unzip -o "$W/$ASSET" bootloader.bin partitions.bin firmware.bin -d "$W" >/dev/null

echo "==> downloading boot_app0.bin"
curl -fsSL -o "$W/boot_app0.bin" "$BOOT_APP0_URL"

PORT="${1:-$(ls /dev/cu.usbmodem* 2>/dev/null | head -1 || true)}"
if [ -z "$PORT" ]; then
  echo "!! No /dev/cu.usbmodem* found."
  echo "   Put the dongle in boot mode (hold button, plug in, wait 1s, release),"
  echo "   then pass the port:  ./flash.sh /dev/cu.usbmodemXXXX"
  exit 1
fi

ESPTOOL=(esptool.py)
command -v esptool.py >/dev/null 2>&1 || ESPTOOL=(python3 -m esptool)

echo "==> flashing on $PORT (esp32s3)"
"${ESPTOOL[@]}" --chip esp32s3 --port "$PORT" --baud 921600 write_flash \
  0x0     "$W/bootloader.bin" \
  0x8000  "$W/partitions.bin" \
  0xe000  "$W/boot_app0.bin" \
  0x10000 "$W/firmware.bin"

echo "==> done! Unplug/replug the dongle."
echo "    Join WiFi 'iPhone14' (password 'password') and open http://4.3.2.1:8080"
