#!/usr/bin/env bash
# Install a curated set of NON-cybersec apps: media/torrent, dev/sysadmin, daily.
# FOSS-first — F-Droid apps by package id (F-Droid API), a few via GitHub.
# Idempotent — skips installed. Needs: adb, gh, curl, python3.  Usage: ./extras.sh
set -uo pipefail
ADB=""; for c in adb "$HOME/Library/Android/sdk/platform-tools/adb" /opt/homebrew/bin/adb; do
  command -v "$c" >/dev/null 2>&1 && { ADB="$c"; break; }; [ -x "$c" ] && { ADB="$c"; break; }; done
[ -n "$ADB" ] || { echo "adb not found"; exit 1; }
[ "$("$ADB" get-state 2>/dev/null)" = device ] || { echo "No device — connect adb."; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pkgs="$("$ADB" shell pm list packages 2>/dev/null)"
has(){ echo "$pkgs" | grep -q "package:$1"; }
pick(){ find "$TMP" -maxdepth 1 -type f -name '*.apk' 2>/dev/null | grep -viE 'debug|x86|armeabi|SafeSites' | grep -iE 'arm64|universal' | head -1; }

fdroid(){ local pkg="$1" label="$2" vc
  has "$pkg" && { echo "  $label: already installed"; return; }
  vc=$(curl -fsSL "https://f-droid.org/api/v1/packages/$pkg" 2>/dev/null | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('suggestedVersionCode') or d['packages'][0]['versionCode'])" 2>/dev/null)
  [ -n "$vc" ] && curl -fSL -o "$TMP/a.apk" "https://f-droid.org/repo/${pkg}_${vc}.apk" 2>/dev/null
  { [ -f "$TMP/a.apk" ] && "$ADB" install -r "$TMP/a.apk" >/dev/null 2>&1 && echo "  $label: installed"; } || echo "  $label: FAILED (F-Droid app)"
  rm -f "$TMP"/*.apk
}
ghub(){ local pkg="$1" label="$2" repo="$3" pat="$4" apk
  has "$pkg" && { echo "  $label: already installed"; return; }
  find "$TMP" -name '*.apk' -delete 2>/dev/null
  gh release download --repo "$repo" --pattern "$pat" --dir "$TMP" --clobber 2>/dev/null \
    || gh release download --repo "$repo" --pattern '*.apk' --dir "$TMP" --clobber 2>/dev/null
  apk="$(pick)"; [ -z "$apk" ] && apk="$(find "$TMP" -name '*.apk' | head -1)"
  { [ -n "$apk" ] && "$ADB" install -r "$apk" >/dev/null 2>&1 && echo "  $label: installed"; } || echo "  $label: FAILED ($repo)"
  find "$TMP" -name '*.apk' -delete 2>/dev/null
}

echo "== Media / entertainment / torrenting =="
ghub   org.proninyaroslav.libretorrent "LibreTorrent (torrent client)" "proninyaroslav/libretorrent" "*.apk"
fdroid com.github.libretube             "LibreTube (YouTube)"
fdroid de.danoeh.antennapod             "AntennaPod (podcasts)"

echo "== Dev / sysadmin / Linux =="
ghub   com.foxdebug.acode "Acode (code editor)"     "deadlyjack/Acode"  "*.apk"
fdroid org.connectbot                   "ConnectBot (SSH)"
ghub   com.carriez.flutter_hbb "RustDesk (remote desktop)" "rustdesk/rustdesk" "*arm64*.apk"

echo "== Daily / non-tech =="
fdroid com.beemdevelopment.aegis        "Aegis (2FA)"
fdroid com.kunzisoft.keepass.libre      "KeePassDX (passwords)"
fdroid app.organicmaps                  "Organic Maps (offline maps)"
fdroid net.cozic.joplin                 "Joplin (notes)"
fdroid org.breezyweather                "Breezy Weather"
ghub   org.koreader.launcher "KOReader (ebooks)" "koreader/koreader" "*arm64*.apk"

echo
echo "One tap in F-Droid (multi-abi, F-Droid auto-picks the right build): VLC, WireGuard."
echo "Stremio: install from stremio.com, then add the Torrentio addon for torrent streaming."
echo "Dev shell: in Termux run  pkg install nodejs python go rust git neovim tmux openssh"
