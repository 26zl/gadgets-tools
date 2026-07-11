#!/usr/bin/env bash
# Guided Kali NetHunter (re)install / LineageOS upgrade for Galaxy S10 (beyond1lte).
# Run interactively (the vbmeta flash needs a local shell): ./upgrade.sh
# Runs the computer-side commands, pauses for the on-phone taps. See README for details.
# Needs: adb, heimdall (sudo port install Heimdall), gh, curl, python3.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$HOME/nethunter-s10"

ADB=""; for c in adb "$HOME/Library/Android/sdk/platform-tools/adb" /opt/homebrew/bin/adb; do command -v "$c" >/dev/null 2>&1 && { ADB="$c"; break; }; [ -x "$c" ] && { ADB="$c"; break; }; done
HD="";  for c in heimdall /opt/local/bin/heimdall; do command -v "$c" >/dev/null 2>&1 && { HD="$c"; break; }; [ -x "$c" ] && { HD="$c"; break; }; done
[ -n "$ADB" ] || { echo "adb not found (brew install android-platform-tools)"; exit 1; }
[ -n "$HD"  ] || { echo "heimdall not found (sudo port install Heimdall)"; exit 1; }

ok(){   printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
step(){ printf '\n\033[1;36m[STEP] %s\033[0m\n' "$*"; read -rp '       Press Enter when done... ' _; }
wait_auth(){ printf '       waiting for phone (approve the USB-debugging prompt if shown)...\n'; until [ "$("$ADB" get-state 2>/dev/null)" = device ]; do sleep 2; done; }

ok "Galaxy S10 NetHunter — guided upgrade"
echo "adb=$ADB   heimdall=$($HD version 2>&1 | tail -1)"

ok "Current state"
"$HERE/verify.sh" || echo "(phone not connected / not booted — fine for a fresh install)"

step "Download latest files (LineageOS, Magisk v30.7+, vbmeta, Kali installer) to $DIR"
"$HERE/prepare-upgrade.sh" "$DIR"
cd "$DIR"
LIN=$(ls -t lineage-*-beyond1lte-signed.zip 2>/dev/null | head -1)
MAG=$(ls -t Magisk-v*.apk 2>/dev/null | head -1)
KAL=$(ls -t kali-nethunter-*full.zip 2>/dev/null | head -1)
echo "  LineageOS: ${LIN:-MISSING}"; echo "  Magisk:    ${MAG:-MISSING}"; echo "  Kali:      ${KAL:-MISSING}"
[ -n "$LIN" ] && [ -n "$MAG" ] && [ -n "$KAL" ] || { echo "Some files missing — check prepare-upgrade output."; exit 1; }

step "Put the phone in DOWNLOAD mode (Vol-Down + Bixby + USB, then Vol-Up)"
"$HD" flash --RECOVERY recovery.img --VBMETA vbmeta.img --no-reboot

step "Boot RECOVERY (Vol-Down+Power 7s, then Vol-Up+Bixby+Power). Wipe > Format everything. Apply update > Apply from ADB (tap ALLOW on the adb prompt!)"
"$ADB" -d sideload "$LIN"

step "Reboot System. Finish setup, connect WiFi, enable USB debugging (approve the Mac)"
wait_auth
ok "Installing Magisk app + pushing boot.img"
"$ADB" install -r "$MAG"
"$ADB" push boot.img /sdcard/Download/

step "Open Magisk ($MAG) > Install > Select and Patch a File > Download/boot.img > LET'S GO. Wait for 'All done'"
PATCHED=$("$ADB" shell 'ls /sdcard/Download/magisk_patched*.img 2>/dev/null' | tr -d '\r' | tail -1)
[ -n "$PATCHED" ] || { echo "No magisk_patched*.img found — did the patch finish?"; exit 1; }
"$ADB" pull "$PATCHED" ./magisk_patched.img

step "Put the phone in DOWNLOAD mode again"
"$HD" flash --BOOT magisk_patched.img

step "Let it boot (rooted now). Open Magisk > Direct Install if asked. Enable USB debugging"
wait_auth
ok "Pushing Kali NetHunter installer (~2 GB)"
"$ADB" push "$KAL" /sdcard/

step "Magisk > Modules > Install from Storage > $(basename "$KAL") > reboot. Wait until booted + USB debugging on"
wait_auth

ok "Verifying"
"$HERE/verify.sh"
ok "Done. If anything bootloops: flash the clean boot.img back ($HD flash --BOOT boot.img) and check the README notes."
