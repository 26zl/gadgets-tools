#!/usr/bin/env bash
# Flash USBArmyKnife onto a T-Dongle-S3 in boot mode (hold button, plug in): ./flash.sh [port]
set -euo pipefail

REPO="i-am-shodan/USBArmyKnife"
ASSET="LILYGO-T-Dongle-S3.Firmware.binaries.zip"
# Firmware is pinned to a tested release and its published SHA256 is verified before flashing.
# TODO(maintainer): set TAG to the release tag you tested and ASSET_SHA256 to that release's
# published SHA256 for "$ASSET". The script refuses to flash until both are set, so it never
# flashes an unpinned "latest" or an unverified firmware.
TAG=""
ASSET_SHA256=""
# boot_app0 is pinned to a release tag + checksum (was a mutable 'master' ref).
BOOT_APP0_URL="https://raw.githubusercontent.com/espressif/arduino-esp32/3.2.0/tools/partitions/boot_app0.bin"
BOOT_APP0_SHA256="f94c5d786a7a8fab06ac5d10e33bf37711a6697636dc037559ea19cc410a17f0"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
sha256() { command -v sha256sum >/dev/null 2>&1 && sha256sum "$@" || shasum -a 256 "$@"; }

[ -n "$TAG" ] || { echo "!! TAG is unset — edit flash.sh to pin a tested release tag (see TODO)."; exit 1; }
[ -n "$ASSET_SHA256" ] || { echo "!! ASSET_SHA256 is unset — edit flash.sh to pin the firmware checksum (see TODO)."; exit 1; }

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
