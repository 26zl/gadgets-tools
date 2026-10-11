#!/usr/bin/env bash
# Download everything for a Kali NetHunter (re)install on beyond1lte / LineageOS 23.x (Android 16).
# Requires Magisk v30.7+ (v28.1 bootloops on Android 16). Flash per README.
# Needs: gh, curl, python3.
set -euo pipefail
DIR="${1:-$HOME/nethunter-s10}"; mkdir -p "$DIR"; cd "$DIR"

sha256() { command -v sha256sum >/dev/null 2>&1 && sha256sum "$@" || shasum -a 256 "$@"; }
verify() { # <file> <expected-sha256>
  local got
  got="$(sha256 "$1" | awk '{print $1}')"
  [ "$got" = "$2" ] || { echo "!! checksum mismatch for $1 (expected $2, got $got) — aborting"; exit 1; }
  echo "   verified $1"
}

echo "==> LineageOS beyond1lte (latest) — rom + recovery + boot"
curl -fsSL "https://download.lineageos.org/api/v2/devices/beyond1lte/builds" | python3 -c "
import sys,json
d=json.load(sys.stdin); b=d if isinstance(d,list) else d.get('builds',[])
latest=max(b,key=lambda x:x.get('date',''))
for f in latest['files']:
    if f['filename'].endswith('signed.zip') or f['filename'] in ('recovery.img','boot.img'):
        print(f['url'], f.get('sha256',''))
" | while read -r u h; do
  echo "   $(basename "$u")"
  curl -fsSL -O "$u"
  [ -n "$h" ] || { echo "   !! no sha256 published for $(basename "$u") — aborting"; exit 1; }
  verify "$(basename "$u")" "$h"
done

echo "==> Magisk latest (v30.7+ required for Android 16)"
# TODO(maintainer): topjohnwu/Magisk ships no per-asset SHA256 to verify against; gh fetches over
# TLS from the named repo. Pin --pattern to the exact tested version and verify its published hash.
gh release download --repo topjohnwu/Magisk --dir . --skip-existing --pattern 'Magisk-v*.apk'

echo "==> vbmeta (AVB-disabling)"
# TODO(maintainer): this release ships no SHA256 for vbmeta.img; gh fetches over TLS from the
# pinned tag. Record and verify the hash of the vbmeta.img you tested.
gh release download nethunter-23.0 --repo V0lk3n/nethunter_kernel_samsung_exynos9820 --dir . --skip-existing --pattern 'vbmeta.img'

echo "==> Kali NetHunter kalifs_full installer (URL from get-kali)"
KURL=$(curl -fsSL https://www.kali.org/get-kali/ | grep -oiE "https://[^\"' ]*beyond1lte[^\"' ]*full\.zip" | sort -u | head -1 || true)
if [ -n "$KURL" ]; then
  echo "   $(basename "$KURL")"
  curl -fsSL -O "$KURL"
  # TODO(maintainer): verify the kalifs against Kali's published SHA256SUMS before flashing — the
  # scraped page provides no checksum next to the URL.
else
  echo "   !! not found automatically — grab it from https://www.kali.org/get-kali/"
fi

echo ""; ls -la
echo "Done -> flash per README (heimdall recovery+vbmeta, Magisk v30.7 patch, kalifs module)."
