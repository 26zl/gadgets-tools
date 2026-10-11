#!/usr/bin/env bash
# Flash Bruce onto an M5StickC PLUS2 (plug in via USB): ./flash.sh [port]
set -euo pipefail

REPO="BruceDevices/firmware"
ASSET="Bruce-m5stack-cplus2.bin"
# Firmware is pinned to a tested release and its published SHA256 is verified before flashing.
# TODO(maintainer): set TAG to the release tag you tested and ASSET_SHA256 to that release's
# published SHA256 for "$ASSET". The script refuses to flash until both are set, so it never
# flashes an unpinned "latest" or an unverified image.
TAG=""
ASSET_SHA256=""
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
sha256() { command -v sha256sum >/dev/null 2>&1 && sha256sum "$@" || shasum -a 256 "$@"; }

[ -n "$TAG" ] || { echo "!! TAG is unset — edit flash.sh to pin a tested release tag (see TODO)."; exit 1; }
[ -n "$ASSET_SHA256" ] || { echo "!! ASSET_SHA256 is unset — edit flash.sh to pin the release checksum (see TODO)."; exit 1; }

echo "==> downloading Bruce ($ASSET, $TAG)"
gh release download "$TAG" --repo "$REPO" --pattern "$ASSET" --dir "$W"
echo "==> verifying $ASSET"
[ "$(sha256 "$W/$ASSET" | awk '{print $1}')" = "$ASSET_SHA256" ] \
  || { echo "!! $ASSET checksum mismatch — aborting"; exit 1; }

if [ "$#" -ge 1 ]; then
  PORT="$1"
else
  PORTS="$(ls /dev/cu.usbserial* /dev/cu.wchusbserial* /dev/cu.SLAB_USBtoUART* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || true)"
  N="$(printf '%s\n' "$PORTS" | grep -c . || true)"
  if [ "$N" -eq 0 ]; then
    echo "!! No serial port found. Plug in the StickC and pass the port:"
    echo "   ./flash.sh /dev/cu.usbserial-XXXX"
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

read -rp "==> Flash $ASSET to $PORT? [y/N] " reply || reply=""
case "$reply" in y | Y | yes | YES) ;; *) echo "aborted."; exit 1 ;; esac

echo "==> flashing on $PORT (esp32, merged image @ 0x0)"
"${ESPTOOL[@]}" --chip esp32 --port "$PORT" --baud 921600 write_flash 0x0 "$W/$ASSET"

echo "==> done! The StickC reboots into Bruce's on-screen menu."
echo "    (If it hangs, press the reset/power button.)"
