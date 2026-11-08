#!/usr/bin/env bash
# Download everything for a Kali NetHunter (re)install on beyond1lte / LineageOS 23.x (Android 16).
# Requires Magisk v30.7+ (v28.1 bootloops on Android 16). Flash per README.
# Every file is checked against a trusted SHA-256 and listed in verified.sha256, which
# upgrade.sh re-checks before flashing. Needs: gh, curl, python3.
set -euo pipefail
DIR="${1:-$HOME/nethunter-s10}"; mkdir -p "$DIR"; cd "$DIR"

# Keep each pinned release and its trusted checksum together when updating.
MAGISK_TAG="v30.7"   # sha256 = GitHub release digest of Magisk-v30.7.apk
MAGISK_SHA256="e0d32d2123532860f97123d927b1bb86c4e08e6fd8a48bfc6b5bee0afae9ebd5"
VBMETA_TAG="nethunter-23.0"   # sha256 = GitHub release digest of its vbmeta.img
VBMETA_SHA256="86887bf12fc25b1a03a74e8cca760d354f81243c4984cd5555c908c79697f417"
NH_IMAGES="https://kali.download/nethunter-images/current"

sha256() { command -v sha256sum >/dev/null 2>&1 && sha256sum "$@" || shasum -a 256 "$@"; }
have() { [ -f "$1" ] && [ "$(sha256 "$1" | awk '{print $1}')" = "$2" ]; }
verify() { # <file> <expected-sha256>
  local got
  got="$(sha256 "$1" | awk '{print $1}')"
  [ "$got" = "$2" ] || { echo "!! checksum mismatch for $1 (expected $2, got $got) — aborting"; exit 1; }
  printf '%s  %s\n' "$2" "$1" >> verified.sha256
  echo "   verified $1"
}
: > verified.sha256

echo "==> LineageOS beyond1lte (latest) — rom + recovery + boot"
curl -fsSL "https://download.lineageos.org/api/v2/devices/beyond1lte/builds" | python3 -c "
import sys,json
d=json.load(sys.stdin); b=d if isinstance(d,list) else d.get('builds',[])
latest=max(b,key=lambda x:x.get('date',''))
for f in latest['files']:
    if f['filename'].endswith('signed.zip') or f['filename'] in ('recovery.img','boot.img'):
        print(f['url'], f.get('sha256',''))
" | while read -r u h; do
  f="$(basename "$u")"
  echo "   $f"
  [ -n "$h" ] || { echo "   !! no sha256 published for $f — aborting"; exit 1; }
  have "$f" "$h" || curl -fsSL -o "$f" "$u"
  verify "$f" "$h"
done

echo "==> Magisk $MAGISK_TAG (v30.7+ required for Android 16)"
have "Magisk-$MAGISK_TAG.apk" "$MAGISK_SHA256" \
  || gh release download "$MAGISK_TAG" --repo topjohnwu/Magisk --dir . --clobber --pattern "Magisk-$MAGISK_TAG.apk"
verify "Magisk-$MAGISK_TAG.apk" "$MAGISK_SHA256"

echo "==> vbmeta (AVB-disabling, $VBMETA_TAG)"
have vbmeta.img "$VBMETA_SHA256" \
  || gh release download "$VBMETA_TAG" --repo V0lk3n/nethunter_kernel_samsung_exynos9820 --dir . --clobber --pattern vbmeta.img
verify vbmeta.img "$VBMETA_SHA256"

echo "==> Kali NetHunter kalifs_full installer (from $NH_IMAGES/SHA256SUMS)"
KLINE=$(curl -fsSL "$NH_IMAGES/SHA256SUMS" | grep -E '  kali-nethunter-[^ ]*beyond1lte[^ ]*full\.zip$' | head -1 || true)
[ -n "$KLINE" ] || { echo "   !! no beyond1lte full image listed in $NH_IMAGES/SHA256SUMS — aborting"; exit 1; }
KSHA="${KLINE%% *}"; KFILE="${KLINE##* }"
echo "   $KFILE"
have "$KFILE" "$KSHA" || curl -fsSL -o "$KFILE" "$NH_IMAGES/$KFILE"
verify "$KFILE" "$KSHA"

echo ""; ls -la
echo "Done -> flash per README (heimdall recovery+vbmeta, Magisk $MAGISK_TAG patch, kalifs module)."
echo "Verified files are listed in $DIR/verified.sha256."
