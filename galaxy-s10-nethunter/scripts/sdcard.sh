#!/usr/bin/env bash
# Shuttle files to the phone's microSD to save internal storage.
# Auto-detects the SD volume (works after you swap cards — new UUID is fine).
# Usage:
#   ./sdcard.sh info                  # SD path + free space
#   ./sdcard.sh push <file>...        # copy Mac file(s) -> SD
#   ./sdcard.sh move <phone-path>...  # move an on-phone file -> SD (frees internal)
set -uo pipefail
ADB=""; for c in adb "$HOME/Library/Android/sdk/platform-tools/adb" /opt/homebrew/bin/adb; do
  command -v "$c" >/dev/null 2>&1 && { ADB="$c"; break; }; [ -x "$c" ] && { ADB="$c"; break; }; done
[ -n "$ADB" ] || { echo "adb not found"; exit 1; }
[ "$("$ADB" get-state 2>/dev/null)" = device ] || { echo "No device — connect adb."; exit 1; }

# Auto-detect the microSD mount: /storage/XXXX-XXXX (not 'emulated' or 'self')
SD="$("$ADB" shell 'ls -d /storage/[0-9A-Fa-f]*-[0-9A-Fa-f]* 2>/dev/null | head -1' | tr -d '\r')"
[ -n "$SD" ] || { echo "No microSD detected — insert & mount a card first."; exit 1; }

cmd="${1:-info}"; [ $# -gt 0 ] && shift
case "$cmd" in
  info) echo "SD: $SD"; "$ADB" shell "df -h '$SD' 2>/dev/null | tail -1" ;;
  push)
    for f in "$@"; do
      b="$(basename "$f")"
      echo "push $b -> $SD/"
      "$ADB" push "$f" "/data/local/tmp/$b" >/dev/null \
        && "$ADB" shell su -c "mv '/data/local/tmp/$b' '$SD/' && echo '  ok' || echo '  FAILED (SD full/write?)'"
    done ;;
  move)
    for p in "$@"; do
      echo "move $p -> $SD/"
      "$ADB" shell su -c "mv '$p' '$SD/' && echo '  ok' || echo '  FAILED'"
    done ;;
  *) echo "usage: $0 {info|push <file>...|move <phone-path>...}"; exit 1 ;;
esac
