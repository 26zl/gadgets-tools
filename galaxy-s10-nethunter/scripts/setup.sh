#!/usr/bin/env bash
# Post-install provisioning for the Galaxy S10 NetHunter rig.
# Run AFTER LineageOS + NetHunter are installed and booted (see upgrade.sh).
# Installs the userspace tools the rig needs that aren't in the base image,
# ships the bundled tools + phone-doctor into the chroot, then verifies.
# Idempotent — safe to re-run.  Usage:  ./setup.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S10="$(cd "$HERE/.." && pwd)"   # the galaxy-s10-nethunter/ dir (submodules live here)
K=/data/local/nhsystem/kali-arm64

ADB=""; for c in adb "$HOME/Library/Android/sdk/platform-tools/adb" /opt/homebrew/bin/adb /usr/local/bin/adb /usr/lib/android-sdk/platform-tools/adb "$HOME/Android/Sdk/platform-tools/adb"; do
  command -v "$c" >/dev/null 2>&1 && { ADB="$c"; break; }; [ -x "$c" ] && { ADB="$c"; break; }; done
[ -n "$ADB" ] || { echo "adb not found (brew install android-platform-tools; Linux/WSL: sudo apt install adb)"; exit 1; }
[ "$("$ADB" get-state 2>/dev/null)" = device ] || { echo "No device — connect adb (USB or wireless) and approve the prompt."; exit 1; }
step(){ printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

step "1/6  Update git submodules"
git -C "$S10" submodule update --init --recursive
git -C "$S10" submodule status | sed 's/^/    /'

step "2/6  Prepare the Kali chroot (bind mounts + DNS)"
"$ADB" shell su -c "K=$K; for m in proc sys dev dev/pts; do grep -q \" \$K/\$m \" /proc/mounts || mount -o bind /\$m \$K/\$m; done; grep -q nameserver \$K/etc/resolv.conf 2>/dev/null || printf 'nameserver 1.1.1.1\n' > \$K/etc/resolv.conf; echo '    chroot ready'"

step "3/6  Install base packages in the chroot (apt)"
PROV="$(mktemp)"
cat > "$PROV" <<'CHROOT'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
# kalifs_full already ships nmap, aircrack-ng, wifite, reaver, gpsd, kismet, bettercap —
# so only install the gaps + Python install tooling + cgps client:
apt-get install -y --no-install-recommends masscan pipx python3-pip git curl gpsd-clients bluez || true
# optional: PDF-report libs for netsec-auditor (weasyprint). Remove if you don't want PDF.
apt-get install -y --no-install-recommends libpango-1.0-0 libpangocairo-1.0-0 libharfbuzz0b fonts-dejavu || true
pipx ensurepath >/dev/null 2>&1 || true
echo "== apt provisioning done =="
CHROOT
"$ADB" push "$PROV" /data/local/tmp/chroot-provision.sh >/dev/null
"$ADB" shell su -c "cp /data/local/tmp/chroot-provision.sh $K/root/ && chroot $K /bin/bash /root/chroot-provision.sh" 2>&1 | tail -20
rm -f "$PROV"

step "4/6  Install bundled tools into the chroot"
ship(){ # $1=submodule dir  $2=chroot dest name
  local d="$S10/$1"
  [ -d "$d/.git" ] || [ -f "$d/.git" ] || { echo "    ($1 submodule not checked out — run: git submodule update --init)"; return; }
  git -C "$d" archive HEAD -o "/tmp/$2.tar" || return
  "$ADB" push "/tmp/$2.tar" "/data/local/tmp/$2.tar" >/dev/null
  "$ADB" shell su -c "K=$K; rm -rf \$K/root/$2; mkdir -p \$K/root/$2; tar xf /data/local/tmp/$2.tar -C \$K/root/$2"
  rm -f "/tmp/$2.tar"
}
ship netsec-auditor netsec-auditor
echo "    installing netsec-auditor..."
"$ADB" shell su -c "chroot $K /bin/bash -lc 'cd /root/netsec-auditor && (pipx install \".[all]\" || pipx install \".[wireless]\" || pip install --break-system-packages \".[wireless]\" || pip install --break-system-packages .)'" 2>&1 | tail -6
ship cybersec-toolkit cybersec-toolkit
echo "    cybersec-toolkit source at (chroot) /root/cybersec-toolkit — run its ./install.sh with a profile yourself (it can pull 580+ tools)"

step "5/6  Deploy phone-doctor.sh"
"$ADB" push "$HERE/phone-doctor.sh" /data/local/tmp/phone-doctor.sh >/dev/null
"$ADB" shell su -c "cp /data/local/tmp/phone-doctor.sh $K/root/phone-doctor.sh; chmod +x $K/root/phone-doctor.sh; echo '    at (chroot) /root/phone-doctor.sh + /data/local/tmp/phone-doctor.sh'"

step "6/6  Verify"
"$HERE/verify.sh" || true
"$ADB" shell su -c 'sh /data/local/tmp/phone-doctor.sh' 2>&1

echo
echo "Done. gpsd for wardriving:  adb shell su -c 'chroot $K /bin/bash -lc \"gpsd -n /dev/ttyACM0 && cgps\"'"
echo "Cleanup tmp:  adb shell su -c 'rm -f /data/local/tmp/*.tar /data/local/tmp/chroot-provision.sh'"
