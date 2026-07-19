#!/usr/bin/env bash
# Install the Android app pack via adb from official sources (GitHub/GitLab/F-Droid).
# Idempotent — skips apps already installed. Needs: adb, gh, curl, python3.
# Magisk modules (LSPosed, PlayIntegrityFix, Shamiko) are NOT here — install via the Magisk app.
# Usage: ./apps.sh
set -uo pipefail
ADB=""; for c in adb "$HOME/Library/Android/sdk/platform-tools/adb" /opt/homebrew/bin/adb; do
  command -v "$c" >/dev/null 2>&1 && { ADB="$c"; break; }; [ -x "$c" ] && { ADB="$c"; break; }; done
[ -n "$ADB" ] || { echo "adb not found (brew install android-platform-tools)"; exit 1; }
[ "$("$ADB" get-state 2>/dev/null)" = device ] || { echo "No device — connect adb and approve."; exit 1; }
command -v gh >/dev/null || { echo "gh (GitHub CLI) required"; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pkgs="$("$ADB" shell pm list packages 2>/dev/null)"
has(){ echo "$pkgs" | grep -q "package:$1"; }

pick_best(){ # choose the arm64/universal, non-debug apk in $TMP
  local f
  f=$(find "$TMP" -maxdepth 1 -type f -name '*.apk' 2>/dev/null | grep -viE 'debug|x86|armeabi|playstore|SafeSites' | grep -iE 'arm64|universal|ChromePublic' | head -1)
  [ -z "$f" ] && f=$(find "$TMP" -maxdepth 1 -type f -name '*.apk' 2>/dev/null | grep -viE 'debug|x86|armeabi|playstore' | head -1)
  [ -z "$f" ] && f=$(find "$TMP" -maxdepth 1 -type f -name '*.apk' 2>/dev/null | head -1)
  echo "$f"
}
install_apk(){ local label="$1" apk="$2"
  { [ -n "$apk" ] && [ -f "$apk" ] && "$ADB" install -r "$apk" >/dev/null 2>&1 && echo "  $label: installed"; } \
    || echo "  $label: FAILED (grab from F-Droid)"
}

# F-Droid (direct)
if has org.fdroid.fdroid; then echo "  F-Droid: already installed"; else
  rm -f "$TMP"/*.apk; curl -fsSL -o "$TMP/fdroid.apk" https://f-droid.org/F-Droid.apk && install_apk "F-Droid" "$TMP/fdroid.apk"
fi
# Aurora Store (F-Droid repo — reliable)
if has com.aurora.store; then echo "  Aurora Store: already installed"; else
  rm -f "$TMP"/*.apk
  vc=$(curl -fsSL "https://f-droid.org/api/v1/packages/com.aurora.store" 2>/dev/null \
        | python3 -c "import sys,json;print(json.load(sys.stdin)['packages'][0]['versionCode'])" 2>/dev/null)
  [ -n "$vc" ] && curl -fSL -o "$TMP/aurora.apk" "https://f-droid.org/repo/com.aurora.store_${vc}.apk" 2>/dev/null
  install_apk "Aurora Store" "$TMP/aurora.apk"
fi

# GitHub apps:  pkgid | label | owner/repo | preferred-glob
GH_APPS=(
  "dev.imranr.obtainium|Obtainium|ImranR98/Obtainium|*arm64-v8a-release.apk"
  "com.termux|Termux|termux/termux-app|*universal*.apk"
  "org.adaway|AdAway|AdAway/AdAway|*.apk"
  "com.celzero.bravedns|RethinkDNS|celzero/rethink-app|*website*.apk"
  "com.termux.api|Termux:API|termux/termux-api|*.apk"
  "com.termux.boot|Termux:Boot|termux/termux-boot|*.apk"
  "eu.darken.sdmse|SD Maid SE|d4rken-org/sdmaid-se|*foss-release.apk"
  "moe.shizuku.privileged.api|Shizuku|RikkaApps/Shizuku|shizuku-*.apk"
  "io.github.muntashirakon.AppManager|App Manager|MuntashirAkon/AppManager|AppManager_v*.apk"
  "net.mullvad.mullvadvpn|Mullvad VPN|mullvad/mullvadvpn-app|MullvadVPN-*.apk"
  "org.cromite.cromite|Cromite|uazo/cromite|arm64_ChromePublic.apk"
  "mattecarra.accapp|AccA|MatteCarra/AccA|*.apk"
  "me.zhanghai.android.files|Material Files|zhanghai/MaterialFiles|*.apk"
  "com.emanuelef.remote_capture|PCAPdroid|emanuelef/PCAPdroid|*.apk"
  "com.looker.droidify|Droid-ify|Droid-ify/Droid-ify|*.apk"
  "dev.ukanth.ufirewall|AFWall+|ukanth/afwall|*.apk"
  "net.wigle.wigleandroid|WiGLE WiFi (wardriving)|wiglenet/wigle-wifi-wardriving|*.apk"
)
for e in "${GH_APPS[@]}"; do
  IFS='|' read -r pkg label repo pat <<< "$e"
  if has "$pkg"; then echo "  $label: already installed"; continue; fi
  rm -f "$TMP"/*.apk
  gh release download --repo "$repo" --pattern "$pat" --dir "$TMP" --clobber 2>/dev/null \
    || gh release download --repo "$repo" --pattern '*.apk' --dir "$TMP" --clobber 2>/dev/null
  apk="$(pick_best)"
  if [ -n "$apk" ] && "$ADB" install -r "$apk" >/dev/null 2>&1; then echo "  $label: installed"; else
    rm -f "$TMP"/*.apk   # fallback: F-Droid repo
    vc=$(curl -fsSL "https://f-droid.org/api/v1/packages/$pkg" 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin)['packages'][0]['versionCode'])" 2>/dev/null)
    { [ -n "$vc" ] && curl -fSL -o "$TMP/fd.apk" "https://f-droid.org/repo/${pkg}_${vc}.apk" 2>/dev/null && "$ADB" install -r "$TMP/fd.apk" >/dev/null 2>&1 && echo "  $label: installed (F-Droid)"; } || echo "  $label: FAILED (grab from F-Droid)"
  fi
done

echo
echo "Magisk modules (via Magisk app): LSPosed, PlayIntegrityFix, Shamiko."
echo "Hardened Firefox alternative: IronFox (F-Droid / gitlab.com/ironfox-oss)."
