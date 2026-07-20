#!/usr/bin/env bash
# Set up key-only SSH into the Kali chroot — a stable alternative to wireless adb.
# Runs as root, so it stays reachable past a per-app VPN (e.g. RethinkDNS). Gives a Kali root
# shell + Android's files bind-mounted in (/system and /data — app data at /data/data included);
# Android app-management (pm/am) still needs adb.
# Auto-starts on boot via a Magisk service.d hook it installs.
# Key-only auth. Needs: adb (device connected + approved) and an SSH public key.
# Usage: ./ssh-setup.sh [pubkey-file] [port]   (defaults: ~/.ssh/id_ed25519.pub, 8022)
set -uo pipefail
PUBKEY="${1:-$HOME/.ssh/id_ed25519.pub}"
PORT="${2:-8022}"
K=/data/local/nhsystem/kali-arm64
ADB=""; for c in adb "$HOME/Library/Android/sdk/platform-tools/adb" /opt/homebrew/bin/adb /usr/local/bin/adb /usr/lib/android-sdk/platform-tools/adb "$HOME/Android/Sdk/platform-tools/adb"; do
  command -v "$c" >/dev/null 2>&1 && { ADB="$c"; break; }; [ -x "$c" ] && { ADB="$c"; break; }; done
[ -n "$ADB" ] || { echo "adb not found (brew install android-platform-tools; Linux/WSL: sudo apt install adb)"; exit 1; }
[ "$("$ADB" get-state 2>/dev/null)" = device ] || { echo "No device — connect adb and approve."; exit 1; }
[ -f "$PUBKEY" ] || { echo "No public key at $PUBKEY — generate one: ssh-keygen -t ed25519"; exit 1; }
KEY="$(cat "$PUBKEY")"

# chroot-side setup (key baked in; ed25519 pubkeys carry no shell metacharacters)
TMP="$(mktemp)"; SVC="$(mktemp)"; trap 'rm -f "$TMP" "$SVC"' EXIT
cat > "$TMP" <<INNER
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin   # Kali coreutils, not Android's /system/bin
mkdir -p /root/.ssh /run/sshd && chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
grep -qxF '$KEY' /root/.ssh/authorized_keys || echo '$KEY' >> /root/.ssh/authorized_keys   # append, don't clobber other keys
mkdir -p /etc/ssh/sshd_config.d
printf 'Port %s\nPermitRootLogin prohibit-password\nPubkeyAuthentication yes\nPasswordAuthentication no\n' '$PORT' > /etc/ssh/sshd_config.d/nethunter.conf
pkill -x sshd 2>/dev/null || true
/usr/sbin/sshd && echo "sshd listening on :$PORT"
INNER

echo "==> binding mounts (+ /system and /data for Android files) and starting sshd in the chroot"
# NB: /dev is a SHARED mount — a plain bind lets the chroot's empty binderfs propagate back onto the global
# /dev/binderfs and bury the real binder nodes (every new Android app then SIGABRTs on /dev/binder). toybox
# mount can't set propagation, so rslave the binds via Kali's util-linux mount (same namespace, from the chroot).
"$ADB" shell "su -c 'for m in proc sys dev dev/pts system data; do mkdir -p $K/\$m; grep -q \" $K/\$m \" /proc/mounts || mount -o bind /\$m $K/\$m; done; [ -e $K/data/adb ] || mount -o bind /data $K/data; [ -e $K/system/bin ] || mount -o bind /system $K/system; for m in dev proc sys system data; do chroot $K /usr/bin/mount --make-rslave /\$m 2>/dev/null; done'" >/dev/null 2>&1
"$ADB" push "$TMP" /data/local/tmp/ssh-inner.sh >/dev/null
"$ADB" shell "su -c 'cp /data/local/tmp/ssh-inner.sh $K/root/ssh-inner.sh && chroot $K /bin/bash /root/ssh-inner.sh; rm -f $K/root/ssh-inner.sh /data/local/tmp/ssh-inner.sh'"

# Persist across reboots: a Magisk service.d hook (root -> stays reachable past a per-app VPN).
cat > "$SVC" <<'SVCEOF'
#!/system/bin/sh
K=/data/local/nhsystem/kali-arm64
[ -x "$K/usr/sbin/sshd" ] || exit 0
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 3; done
sleep 5
for m in proc sys dev dev/pts system data; do mkdir -p "$K/$m"; grep -q " $K/$m " /proc/mounts || mount -o bind "/$m" "$K/$m"; done
# a phantom empty mount can shadow Android's /data (and /system) — force the bind if their content isn't visible
[ -e "$K/data/adb" ]   || mount -o bind /data   "$K/data"
[ -e "$K/system/bin" ] || mount -o bind /system "$K/system"
# CRITICAL: /dev is a SHARED mount — a plain bind lets the chroot's empty binderfs propagate back onto the
# global /dev/binderfs and bury the real binder nodes (every new app then SIGABRTs on /dev/binder). toybox
# mount can't set propagation, so rslave the binds via Kali's util-linux mount (same namespace, from the chroot).
for m in dev proc sys system data; do chroot "$K" /usr/bin/mount --make-rslave "/$m" 2>/dev/null; done
mkdir -p "$K/run/sshd"; pkill -x sshd 2>/dev/null; chroot "$K" /usr/sbin/sshd
SVCEOF
"$ADB" push "$SVC" /data/local/tmp/chroot-sshd.sh >/dev/null
"$ADB" shell "su -c 'mkdir -p /data/adb/service.d && cp /data/local/tmp/chroot-sshd.sh /data/adb/service.d/chroot-sshd.sh && chmod 755 /data/adb/service.d/chroot-sshd.sh && rm -f /data/local/tmp/chroot-sshd.sh'"

IP="$("$ADB" shell 'ip -o -4 addr show wlan0 2>/dev/null | grep -oE "inet [0-9.]+" | cut -d" " -f2' | tr -d '\r')"
echo
echo "SSH ready — connect with:  ssh -p $PORT root@${IP:-<phone-wifi-ip>}"
echo "Key-only (no passwords). Auto-starts on boot via a Magisk service.d hook (runs as root, so it stays reachable past a per-app VPN like RethinkDNS)."
