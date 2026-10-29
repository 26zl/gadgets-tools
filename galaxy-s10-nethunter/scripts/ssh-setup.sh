#!/usr/bin/env bash
# Set up key-only SSH into the Kali chroot — a stable alternative to wireless adb.
# Runs as root, so it stays reachable past a per-app VPN (e.g. RethinkDNS). Gives a Kali root
# shell + Android's files bind-mounted in (/system and /data — app data at /data/data included);
# Android app-management (pm/am) still needs adb.
# Auto-starts on boot via a Magisk service.d hook it installs.
# Key-only auth. Needs: adb (device connected + approved) and an SSH public key.
# Usage: ./ssh-setup.sh [pubkey-file] [port]   (defaults: ~/.ssh/id_ed25519.pub, 8022)
set -euo pipefail
PUBKEY="${1:-$HOME/.ssh/id_ed25519.pub}"
PORT="${2:-8022}"
[[ "$PORT" =~ ^[0-9]{1,5}$ ]] && ((10#$PORT >= 1 && 10#$PORT <= 65535)) || { echo "Port must be between 1 and 65535."; exit 1; }
PORT=$((10#$PORT))
K=/data/local/nhsystem/kali-arm64
ADB=""; for c in adb "$HOME/Library/Android/sdk/platform-tools/adb" /opt/homebrew/bin/adb /usr/local/bin/adb /usr/lib/android-sdk/platform-tools/adb "$HOME/Android/Sdk/platform-tools/adb"; do
  command -v "$c" >/dev/null 2>&1 && { ADB="$c"; break; }; [ -x "$c" ] && { ADB="$c"; break; }; done
[ -n "$ADB" ] || { echo "adb not found (brew install android-platform-tools; Linux/WSL: sudo apt install adb)"; exit 1; }
[ "$("$ADB" get-state 2>/dev/null)" = device ] || { echo "No device — connect adb and approve."; exit 1; }
[ -f "$PUBKEY" ] || { echo "No public key at $PUBKEY — generate one: ssh-keygen -t ed25519"; exit 1; }
command -v ssh-keygen >/dev/null || { echo "ssh-keygen is required to validate the public key."; exit 1; }
read -r KEY_TYPE _ < "$PUBKEY" || true
case "$KEY_TYPE" in
  ssh-ed25519|ssh-rsa|ecdsa-sha2-*|sk-*) ;;
  *) echo "Expected an OpenSSH public key file."; exit 1 ;;
esac
ssh-keygen -l -f "$PUBKEY" >/dev/null 2>&1 || { echo "Invalid SSH public key file."; exit 1; }

# Transfer the public key as data so its comment cannot become root shell code.
TMP="$(mktemp)"; SVC="$(mktemp)"; trap 'rm -f "$TMP" "$SVC"' EXIT
cat > "$TMP" <<INNER
#!/bin/bash
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin   # Kali coreutils, not Android's /system/bin
mkdir -p /root/.ssh /run/sshd && chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
while IFS= read -r key || [ -n "\$key" ]; do
  [ -n "\$key" ] || continue
  grep -qxF -- "\$key" /root/.ssh/authorized_keys || printf '%s\\n' "\$key" >> /root/.ssh/authorized_keys
done < /root/ssh-public-key.pub
mkdir -p /etc/ssh/sshd_config.d
printf 'Port %s\nPermitRootLogin prohibit-password\nPubkeyAuthentication yes\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n' '$PORT' > /etc/ssh/sshd_config.d/nethunter.conf
/usr/sbin/sshd -t
pkill -x sshd 2>/dev/null || true
/usr/sbin/sshd && echo "sshd listening on :$PORT"
INNER

echo "==> binding mounts (+ /system and /data for Android files) and starting sshd in the chroot"
# Use Kali's rslave mounts to prevent chroot binderfs mounts from propagating into Android.
"$ADB" shell "su -c 'set -e; for m in proc sys dev dev/pts system data; do mkdir -p $K/\$m; grep -q \" $K/\$m \" /proc/mounts || mount -o bind /\$m $K/\$m; done; [ -e $K/data/adb ] || mount -o bind /data $K/data; [ -e $K/system/bin ] || mount -o bind /system $K/system; for m in dev proc sys system data; do chroot $K /usr/bin/mount --make-rslave /\$m; done'" >/dev/null
"$ADB" push "$TMP" /data/local/tmp/ssh-inner.sh >/dev/null
"$ADB" push "$PUBKEY" /data/local/tmp/ssh-public-key.pub >/dev/null
"$ADB" shell "su -c 'cp /data/local/tmp/ssh-inner.sh $K/root/ssh-inner.sh && cp /data/local/tmp/ssh-public-key.pub $K/root/ssh-public-key.pub && chroot $K /bin/bash /root/ssh-inner.sh; result=\$?; rm -f $K/root/ssh-inner.sh $K/root/ssh-public-key.pub /data/local/tmp/ssh-inner.sh /data/local/tmp/ssh-public-key.pub; exit \$result'"

# Persist across reboots: a Magisk service.d hook (root -> stays reachable past a per-app VPN).
cat > "$SVC" <<'SVCEOF'
#!/system/bin/sh
set -eu
K=/data/local/nhsystem/kali-arm64
[ -x "$K/usr/sbin/sshd" ] || exit 0
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 3; done
sleep 5
for m in proc sys dev dev/pts system data; do mkdir -p "$K/$m"; grep -q " $K/$m " /proc/mounts || mount -o bind "/$m" "$K/$m"; done
# Rebind if an empty mount shadows Android's data or system files.
[ -e "$K/data/adb" ]   || mount -o bind /data   "$K/data"
[ -e "$K/system/bin" ] || mount -o bind /system "$K/system"
# Use Kali's rslave mounts to prevent chroot binderfs mounts from propagating into Android.
for m in dev proc sys system data; do chroot "$K" /usr/bin/mount --make-rslave "/$m"; done
mkdir -p "$K/run/sshd"
chroot "$K" /usr/sbin/sshd -t
pkill -x sshd 2>/dev/null || true
chroot "$K" /usr/sbin/sshd
SVCEOF
"$ADB" push "$SVC" /data/local/tmp/chroot-sshd.sh >/dev/null
"$ADB" shell "su -c 'mkdir -p /data/adb/service.d && cp /data/local/tmp/chroot-sshd.sh /data/adb/service.d/chroot-sshd.sh && chmod 755 /data/adb/service.d/chroot-sshd.sh && rm -f /data/local/tmp/chroot-sshd.sh'"

IP="$("$ADB" shell 'ip -o -4 addr show wlan0 2>/dev/null | grep -oE "inet [0-9.]+" | cut -d" " -f2' | tr -d '\r')"
echo
echo "SSH ready — connect with:  ssh -p $PORT root@${IP:-<phone-wifi-ip>}"
echo "Key-only (no passwords). Auto-starts on boot via a Magisk service.d hook (runs as root, so it stays reachable past a per-app VPN like RethinkDNS)."
