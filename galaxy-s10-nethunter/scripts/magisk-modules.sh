#!/usr/bin/env bash
# Stage the Magisk module zips to the phone's /sdcard/Download for manual install
# in the Magisk app (Modules -> Install from storage). These can't be adb-installed
# (they patch boot/Zygisk). Uses the maintained forks. Needs: adb, gh.  Usage: ./magisk-modules.sh
# Note: PlayIntegrityFork/ReZygisk only matter with Google Play Services or microG — a no-op on a de-Googled phone.
set -uo pipefail
ADB=""; for c in adb "$HOME/Library/Android/sdk/platform-tools/adb" /opt/homebrew/bin/adb /usr/local/bin/adb /usr/lib/android-sdk/platform-tools/adb "$HOME/Android/Sdk/platform-tools/adb"; do
  command -v "$c" >/dev/null 2>&1 && { ADB="$c"; break; }; [ -x "$c" ] && { ADB="$c"; break; }; done
[ -n "$ADB" ] || { echo "adb not found"; exit 1; }
[ "$("$ADB" get-state 2>/dev/null)" = device ] || { echo "No device — connect adb."; exit 1; }
command -v gh >/dev/null || { echo "gh (GitHub CLI) required"; exit 1; }
DL=/sdcard/Download; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
"$ADB" shell mkdir -p "$DL" 2>/dev/null
pick(){ find "$TMP" -maxdepth 1 -type f -name "$1" 2>/dev/null | grep -viE 'debug' | head -1; }
stage(){ local repo="$1" pat="$2" label="$3" z
  find "$TMP" -name '*.zip' -delete 2>/dev/null
  gh release download --repo "$repo" --pattern "$pat" --dir "$TMP" --clobber 2>/dev/null \
    || gh release download --repo "$repo" --pattern '*.zip' --dir "$TMP" --clobber 2>/dev/null
  z="$(pick '*.zip')"
  if [ -n "$z" ]; then "$ADB" push "$z" "$DL/" >/dev/null 2>&1 && echo "  OK   $label -> $(basename "$z")"
  else echo "  MISS $label ($repo)"; fi
}
echo "Staging Magisk module zips -> $DL"
stage "JingMatrix/LSPosed"        "*zygisk-release.zip"  "LSPosed (Vector, Android 16)"
stage "LSPosed/LSPosed.github.io" "Shamiko-*release.zip" "Shamiko (root hiding)"
stage "osm0sis/PlayIntegrityFork" "*.zip"                "PlayIntegrityFork (PIF)"
stage "PerformanC/ReZygisk"       "*release.zip"         "ReZygisk (stronger Zygisk)"
echo
echo "Install: Magisk -> Modules -> Install from storage -> $DL -> reboot."
echo "If you use ReZygisk, DISABLE Magisk's built-in Zygisk (Settings) — they conflict."
"$ADB" shell ls -la "$DL" 2>/dev/null | grep -i '\.zip'
