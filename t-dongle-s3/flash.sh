#!/usr/bin/env bash
# Flash USBArmyKnife onto a T-Dongle-S3 in boot mode (hold button, plug in): ./flash.sh [port]
set -euo pipefail

REPO="i-am-shodan/USBArmyKnife"
ASSET="LILYGO-T-Dongle-S3.Firmware.binaries.zip"
# Keep the release tag and trusted asset checksum together when updating firmware.
TAG="v1.1.5"
ASSET_SHA256="de153d2031c831d0154cba7757b2781a54ce2970ba556adec5c4ce6533adcba7"
# The boot image is verified independently of the firmware archive.
BOOT_APP0_URL="https://raw.githubusercontent.com/espressif/arduino-esp32/3.2.0/tools/partitions/boot_app0.bin"
BOOT_APP0_SHA256="f94c5d786a7a8fab06ac5d10e33bf37711a6697636dc037559ea19cc410a17f0"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
sha256() { command -v sha256sum >/dev/null 2>&1 && sha256sum "$@" || shasum -a 256 "$@"; }

[ -n "$TAG" ] || { echo "!! TAG is unset — pin a release tag in flash.sh."; exit 1; }
[ -n "$ASSET_SHA256" ] || { echo "!! ASSET_SHA256 is unset — pin the firmware checksum in flash.sh."; exit 1; }

echo "==> downloading firmware ($ASSET, $TAG)"
gh release download "$TAG" --repo "$REPO" --pattern "$ASSET" --dir "$W"
echo "==> verifying $ASSET"
[ "$(sha256 "$W/$ASSET" | awk '{print $1}')" = "$ASSET_SHA256" ] \
  || { echo "!! $ASSET checksum mismatch — aborting"; exit 1; }
unzip -o "$W/$ASSET" bootloader.bin partitions.bin firmware.bin -d "$W" >/dev/null

echo "==> downloading boot_app0.bin"
curl -fsSL -o "$W/boot_app0.bin" "$BOOT_APP0_URL"
[ "$(sha256 "$W/boot_app0.bin" | awk '{print $1}')" = "$BOOT_APP0_SHA256" ] \
  || { echo "!! boot_app0.bin checksum mismatch — aborting"; exit 1; }

if [ "$#" -ge 1 ]; then
  PORT="$1"
else
  PORTS="$(ls /dev/cu.usbmodem* /dev/ttyACM* 2>/dev/null || true)"
  N="$(printf '%s\n' "$PORTS" | grep -c . || true)"
  if [ "$N" -eq 0 ]; then
    echo "!! No serial port found (looked for /dev/cu.usbmodem* and /dev/ttyACM*)."
    echo "   Put the dongle in boot mode (hold button, plug in, wait 1s, release),"
    echo "   then pass the port:  ./flash.sh /dev/cu.usbmodemXXXX"
    exit 1
  elif [ "$N" -gt 1 ]; then
    echo "!! Multiple serial ports found — pass the one you want explicitly:"
    printf '%s\n' "$PORTS" | sed 's/^/   /'
    echo "   ./flash.sh <port>"
    exit 1
  fi
  PORT="$PORTS"
fi

if command -v esptool.py >/dev/null 2>&1; then ESPTOOL=(esptool.py)
elif python3 -c 'import esptool' >/dev/null 2>&1; then ESPTOOL=(python3 -m esptool)
else echo "!! esptool not found — install: pip install esptool"; exit 1; fi

read -rp "==> Flash firmware to $PORT (esp32s3)? [y/N] " reply || reply=""
case "$reply" in y | Y | yes | YES) ;; *) echo "aborted."; exit 1 ;; esac

echo "==> flashing on $PORT (esp32s3)"
"${ESPTOOL[@]}" --chip esp32s3 --port "$PORT" --baud 921600 write_flash \
  0x0     "$W/bootloader.bin" \
  0x8000  "$W/partitions.bin" \
  0xe000  "$W/boot_app0.bin" \
  0x10000 "$W/firmware.bin"

echo "==> done! Unplug/replug the dongle."
echo "    Join the WiFi AP the dongle broadcasts, then open http://4.3.2.1:8080"
echo "    Note: a red \"crash dump\" screen right after flashing is a known false"
echo "    positive on v1.1.5 (esptool's JTAG reset) — fully unplug/replug to clear it"
echo "    (USBArmyKnife issue #272)."
