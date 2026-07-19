#!/usr/bin/env bash
# adb health-check for the Galaxy S10 (beyond1lte) Kali NetHunter setup.
# Run after a reinstall to confirm everything is in place.
A=""
for c in adb "$HOME/Library/Android/sdk/platform-tools/adb" /opt/homebrew/bin/adb /usr/local/bin/adb /usr/lib/android-sdk/platform-tools/adb "$HOME/Android/Sdk/platform-tools/adb"; do
  command -v "$c" >/dev/null 2>&1 && { A="$c"; break; }
  [ -x "$c" ] && { A="$c"; break; }
done
[ -n "$A" ] || { echo "adb not found — install: brew install android-platform-tools; Linux/WSL: sudo apt install adb"; exit 1; }
[ "$("$A" get-state 2>/dev/null)" = "device" ] || { echo "No authorized device — plug in, enable USB debugging, approve the prompt."; exit 1; }

g(){ "$A" shell getprop "$1" 2>/dev/null | tr -d '\r'; }
pkgs="$("$A" shell pm list packages 2>/dev/null | tr -d '\r')"
kernel="$("$A" shell uname -r 2>/dev/null | tr -d '\r')"
p(){ printf "%-4s %s\n" "$1" "$2"; }

[ "$(g ro.product.device)" = beyond1lte ] && p OK "device: $(g ro.product.model) ($(g ro.product.device))" \
                                          || p "!!" "device: $(g ro.product.model) — expected beyond1lte"
p "--" "Android $(g ro.build.version.release) · LineageOS $(g ro.lineage.version)"

echo "$kernel" | grep -qiE 'v0lk3n|nethunter|kali' && p OK "NetHunter kernel: $kernel" \
                                                   || p "!!" "kernel: $kernel — NOT a NetHunter kernel"

echo "$pkgs" | grep -q com.topjohnwu.magisk && p OK "Magisk (root)" || p "!!" "Magisk missing"
for x in com.offsec.nethunter com.offsec.nethunter.store com.offsec.nhterm com.offsec.nethunter.kex; do
  echo "$pkgs" | grep -q "$x" && p OK "$x" || p "!!" "$x MISSING"
done
