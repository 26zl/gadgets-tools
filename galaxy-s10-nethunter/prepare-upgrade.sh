#!/usr/bin/env bash
# Download everything for a Kali NetHunter (re)install on beyond1lte / LineageOS 23.x (Android 16).
# KEY: needs Magisk v30.7+ — the Kali guide's v28.1 bootloops on A16. Flash per README.
# Needs: gh, curl, python3.
set -euo pipefail
DIR="${1:-$HOME/nethunter-s10}"; mkdir -p "$DIR"; cd "$DIR"

echo "==> LineageOS beyond1lte (latest) — rom + recovery + boot"
curl -fsSL "https://download.lineageos.org/api/v2/devices/beyond1lte/builds" | python3 -c "
import sys,json
d=json.load(sys.stdin); b=d if isinstance(d,list) else d.get('builds',[])
latest=max(b,key=lambda x:x.get('date',''))
for f in latest['files']:
    if f['filename'].endswith('signed.zip') or f['filename'] in ('recovery.img','boot.img'): print(f['url'])
" | while read -r u; do echo "   $(basename "$u")"; curl -fsSL -O "$u"; done

echo "==> Magisk latest (need v30.7+ for A16 — NOT the guide's v28.1)"
gh release download --repo topjohnwu/Magisk --dir . --skip-existing --pattern 'Magisk-v*.apk'

echo "==> vbmeta (AVB-disabling) from V0lk3n"
gh release download nethunter-23.0 --repo V0lk3n/nethunter_kernel_samsung_exynos9820 --dir . --skip-existing --pattern 'vbmeta.img'

echo "==> Kali NetHunter kalifs_full installer (URL from get-kali)"
KURL=$(curl -fsSL https://www.kali.org/get-kali/ | grep -oiE "https?://[^\"' ]*beyond1lte[^\"' ]*full\.zip" | sort -u | head -1 || true)
if [ -n "$KURL" ]; then echo "   $(basename "$KURL")"; curl -fsSL -O "$KURL"; else echo "   !! not found automatically — grab it from https://www.kali.org/get-kali/"; fi

echo ""; ls -la
echo "Done -> flash per README (heimdall recovery+vbmeta, Magisk v30.7 patch, kalifs module)."
