#!/system/bin/sh
# S10 NetHunter — on-device health check.
# Run ON THE PHONE as root, from an ANDROID shell (not the Kali chroot):
#   NetHunter Terminal -> AndroidSu, or Termux `su`, then:  sh phone-doctor.sh
# It checks the whole rig: device, kernel, root, NetHunter apps, Kali chroot,
# ALFA (wlan2), GPS (ttyACM0), and netsec-auditor.
K=/data/local/nhsystem/kali-arm64
pass=0; fail=0
ok(){  printf '  \033[32mOK\033[0m   %s\n' "$1"; pass=$((pass+1)); }
bad(){ printf '  \033[31m!!\033[0m   %s\n' "$1"; fail=$((fail+1)); }
inf(){ printf '  --   %s\n' "$1"; }

[ "$(id -u)" = 0 ] || { echo "Run as root (AndroidSu / su)."; exit 1; }
uname -a | grep -qi android 2>/dev/null || [ -e /system/build.prop ] || \
  echo "  (warning: run this from the ANDROID shell, not inside the Kali chroot)"

echo "== Device =="
model=$(getprop ro.product.model); dev=$(getprop ro.product.device)
[ "$dev" = beyond1lte ] && ok "device: $model ($dev)" || bad "device: $model (expected beyond1lte)"
inf "Android $(getprop ro.build.version.release) - LineageOS $(getprop ro.lineage.version)"
kr=$(uname -r)
echo "$kr" | grep -qiE 'v0lk3n|nethunter|kali' && ok "kernel: $kr" || bad "kernel: $kr (not NetHunter)"
inf "SELinux: $(getenforce 2>/dev/null)"

echo "== Root / NetHunter apps =="
pkgs=$(pm list packages 2>/dev/null)
echo "$pkgs" | grep -q com.topjohnwu.magisk && ok "Magisk (root)" || bad "Magisk missing"
for p in com.offsec.nethunter com.offsec.nethunter.store com.offsec.nhterm com.offsec.nethunter.kex; do
  echo "$pkgs" | grep -q "$p" && ok "$p" || bad "$p MISSING"
done

echo "== Kali chroot =="
if [ -d "$K" ]; then
  ok "chroot present: $K"
  for m in proc sys dev dev/pts; do
    grep -q " $K/$m " /proc/mounts 2>/dev/null || mount -o bind "/$m" "$K/$m" 2>/dev/null
  done
  pv=$(chroot "$K" /usr/bin/python3 --version 2>&1)
  echo "$pv" | grep -qi python && ok "chroot python: $pv" || bad "chroot python: $pv"
else
  bad "chroot MISSING: $K"
fi

echo "== External WiFi (ALFA -> wlan2) =="
if [ -d /sys/class/net/wlan2 ]; then
  drv=$(readlink -f /sys/class/net/wlan2/device/driver 2>/dev/null); drv=${drv##*/}
  ok "wlan2 present (driver: ${drv:-?})"
  lsusb 2>/dev/null | grep -qi '0bda:0811' && ok "ALFA on USB (0bda:0811)" || inf "ALFA USB id not visible"
else
  bad "wlan2 missing — ALFA not enumerated (powered hub? replug the hub)"
fi

echo "== GPS (VK172 -> /dev/ttyACM0) =="
if [ -e /dev/ttyACM0 ]; then
  ok "/dev/ttyACM0 present"
  lsusb 2>/dev/null | grep -qi '1546:01a7' && ok "VK172 on USB (1546:01a7)" || inf "GPS USB id not visible"
  nmea=$(timeout 3 cat /dev/ttyACM0 2>/dev/null | grep -m1 '^\$G')
  [ -n "$nmea" ] && ok "GPS streaming NMEA (${nmea%%,*})" || inf "no NMEA in 3s (needs sky view / powered hub)"
else
  bad "/dev/ttyACM0 missing — GPS not enumerated"
fi

echo "== netsec-auditor (in chroot) =="
if [ -x "$K/usr/local/bin/netsec-auditor" ]; then
  if chroot "$K" /usr/local/bin/netsec-auditor --version >/dev/null 2>&1; then
    ok "netsec-auditor installed and runs"
  else
    bad "netsec-auditor present but errors — reinstall (see README)"
  fi
else
  inf "netsec-auditor not installed — see galaxy-s10-nethunter/README.md"
fi

echo
if [ "$fail" = 0 ]; then printf '\033[32mAll good\033[0m — %s checks OK.\n' "$pass"
else printf '\033[31m%s problem(s)\033[0m, %s OK — see the !! lines.\n' "$fail" "$pass"; fi
