#!/usr/bin/env bash
# Guided Kali NetHunter (re)install / LineageOS upgrade for Galaxy S10 (beyond1lte).
# Run interactively (the vbmeta flash needs a local shell): ./upgrade.sh
# Runs the computer-side commands, pauses for the on-phone taps. See README for details.
# Needs: adb, heimdall (sudo port install Heimdall; Linux/WSL: sudo apt install heimdall-flash), gh, curl, python3.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$HOME/nethunter-s10"

ADB=""; for c in adb "$HOME/Library/Android/sdk/platform-tools/adb" /opt/homebrew/bin/adb /usr/local/bin/adb /usr/lib/android-sdk/platform-tools/adb "$HOME/Android/Sdk/platform-tools/adb"; do command -v "$c" >/dev/null 2>&1 && { ADB="$c"; break; }; [ -x "$c" ] && { ADB="$c"; break; }; done
HD="";  for c in heimdall /opt/local/bin/heimdall /usr/bin/heimdall; do command -v "$c" >/dev/null 2>&1 && { HD="$c"; break; }; [ -x "$c" ] && { HD="$c"; break; }; done
[ -n "$ADB" ] || { echo "adb not found (brew install android-platform-tools; Linux/WSL: sudo apt install adb)"; exit 1; }
[ -n "$HD"  ] || { echo "heimdall not found (sudo port install Heimdall; Linux/WSL: sudo apt install heimdall-flash)"; exit 1; }

ok(){   printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
step(){ printf '\n\033[1;36m[STEP] %s\033[0m\n' "$*"; read -rp '       Press Enter when done... ' _; }
wait_auth(){ printf '       waiting for phone (approve the USB-debugging prompt if shown)...\n'; until [ "$("$ADB" get-state 2>/dev/null)" = device ]; do sleep 2; done; }
sha256(){ command -v sha256sum >/dev/null 2>&1 && sha256sum "$@" || shasum -a 256 "$@"; }
sha256c(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum -c "$@"; else shasum -a 256 -c "$@"; fi; }

ok "Galaxy S10 NetHunter — guided upgrade"
echo "adb=$ADB   heimdall=$($HD version 2>&1 | tail -1)"

ok "Current state"
"$HERE/verify.sh" || echo "(phone not connected / not booted — fine for a fresh install)"

step "Download the pinned files (LineageOS, Magisk, vbmeta, Kali installer) to $DIR"
"$HERE/prepare-upgrade.sh" "$DIR"
cd "$DIR" || exit 1
# Use only the files prepare-upgrade.sh verified, and re-check them right before flashing.
[ -s verified.sha256 ] || { echo "verified.sha256 missing — run prepare-upgrade.sh."; exit 1; }
sha256c verified.sha256 >/dev/null || { echo "A file no longer matches verified.sha256 — re-run prepare-upgrade.sh."; exit 1; }
pick(){ awk -v re="$1" '$2 ~ re {f = $2} END {print f}' verified.sha256; }
LIN=$(pick '^lineage-.*-beyond1lte-signed[.]zip$')
MAG=$(pick '^Magisk-v.*[.]apk$')
KAL=$(pick '^kali-nethunter-.*full[.]zip$')
for f in recovery.img vbmeta.img boot.img; do
  [ "$(pick "^$f\$")" = "$f" ] || { echo "$f is not in verified.sha256 — re-run prepare-upgrade.sh."; exit 1; }
done
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
# Only a patched image created by this run may be flashed — never a stale one.
patched(){ "$ADB" shell 'ls /sdcard/Download/magisk_patched*.img 2>/dev/null' | tr -d '\r' | sort; }
BEFORE=$(patched || true)
"$ADB" push boot.img /sdcard/Download/
ondev=$("$ADB" shell sha256sum /sdcard/Download/boot.img | tr -d '\r' | awk '{print $1}')
[ "$ondev" = "$(sha256 boot.img | awk '{print $1}')" ] || { echo "boot.img on the phone does not match the verified download — aborting."; exit 1; }

step "Open Magisk ($MAG) > Install > Select and Patch a File > Download/boot.img > LET'S GO. Wait for 'All done'"
PATCHED=$(comm -13 <(printf '%s\n' "$BEFORE") <(patched || true) | grep . || true)
count=$(printf '%s\n' "$PATCHED" | grep -c . || true)
[ "$count" = 1 ] || { echo "Expected exactly one new magisk_patched*.img from this run, found $count — patch again and re-run."; exit 1; }
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
