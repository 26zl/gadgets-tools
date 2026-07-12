# galaxy-s10-nethunter

Kali NetHunter on a **Samsung Galaxy S10 — SM-G973F (`beyond1lte`, Exynos)**, running **LineageOS 23.2 / Android 16**. A repeatable (re)install and upgrade playbook.

## What's running
| Layer | Detail |
| --- | --- |
| ROM | LineageOS 23.2 (`beyond1lte`, Android 16) |
| Root | Magisk **v30.7** |
| NetHunter | official `kalifs_full` — kernel `v0lk3n-beyond1lte_los-23.2`, Kali chroot (`kali-arm64`), apps (app, Store, Terminal, KeX) |
| External WiFi | ALFA AWUS036ACS (RTL8811AU) → `wlan2` — monitor **+ injection** |
| GPS | HiLetgo VK172 (u-blox 7) → `/dev/ttyACM0` — 3D fix |
| Host link | wireless adb (Android 11+ Wireless Debugging) — frees USB-C for the hub |

## Magisk version
The [official Kali S10 guide](https://www.kali.org/docs/nethunter/installing-nethunter-on-the-samsung-galaxy-s10/) says Magisk **v28.1** — that is too old for Android 16 and **bootloops**. Use **Magisk v30.7+**.

## Tools
**Host (macOS):**
- **Heimdall** via **MacPorts** (Homebrew's formula + cask are both dead): `sudo port install Heimdall`
- `adb` (Android platform-tools) · `gh` (GitHub CLI) · `curl` · `python3`

**Hardware:**
- ALFA Network **AWUS036ACS** (RTL8811AU) — external dual-band WiFi, monitor/injection
- HiLetgo **VK172** (u-blox 7) — USB GPS/GNSS receiver
- **Belkin USB-C hub** — runs the ALFA + GPS together off the phone's single USB-C port (use a PD/charge port to power the phone during long sessions — the ALFA is power-hungry)

## Scripts here
| Script | Does |
| --- | --- |
| `upgrade.sh` | Guided (re)install — downloads + walks you through every step, then verifies |
| `prepare-upgrade.sh` | Just download the latest files → `~/nethunter-s10` |
| `verify.sh` | adb health-check (device, kernel, Magisk, NetHunter apps) |

## Install / upgrade
**Easiest:** `./upgrade.sh` — run it interactively (the `vbmeta` / `setenforce` steps need a local shell). Or manually:

1. **Recovery + AVB off** (Download mode):
   ```
   heimdall flash --RECOVERY recovery.img --VBMETA vbmeta.img --no-reboot
   ```
2. **ROM**: boot recovery → Format everything → `adb -d sideload lineage-23.2-*.zip`
   *(or LineageOS Updater in-place — but it re-enables AVB, so re-flash the disabling `vbmeta` before rooting)*
3. **Root**: install **Magisk v30.7** → *Install → Select and Patch a File → `boot.img`* → `heimdall flash --BOOT magisk_patched.img`
4. **NetHunter**: `adb push kali-nethunter-*-full.zip /sdcard/` → Magisk → Modules → Install from Storage → reboot
5. `./verify.sh`

## Peripherals — setup

### Cable-free adb (frees USB-C for the hub)
Developer options → **Wireless debugging**, then on the host:
```
adb pair <ip>:<pairPort> <code>      # from "Pair device with pairing code"
adb connect <ip>:<connectPort>       # main screen — a DIFFERENT port, changes on every WiFi reconnect
```

### External WiFi — ALFA → `wlan2`
Driver is built into the NetHunter kernel; the ALFA just shows up as `wlan2` over the hub. In the **Kali terminal** (raw `iw`/`ip` from adb fails — SELinux/netd):
```
airmon-ng check kill
airmon-ng start wlan2          # stays wlan2 (not wlan2mon)
aireplay-ng --test wlan2       # -> "Injection is working!"
wifite -i wlan2
```
> `airmon-ng check kill` kills the phone's WiFi → **wireless adb drops**. Do host/adb work first.

### GPS — VK172 → `gpsd`
Appears as `/dev/ttyACM0` (cdc_acm, built-in) and streams NMEA. In the **Kali terminal**:
```
gpsd -n /dev/ttyACM0
cgps                           # wait for 3D fix (needs sky view; cold start ~1 min)
airodump-ng --gpsd -w wardrive wlan2
```
Or NetHunter app → **Wardriving**.

## Gotchas
- **Magisk v28.1 bootloops on A16** → v30.7+.
- A Magisk-patched boot needs **AVB disabled** (`vbmeta`); the LineageOS Updater **re-enables** it.
- `--VBMETA` flash and `setenforce 0` weaken security — run them manually.
- USB plugged in during a force-reboot → Samsung jumps to Download mode. Unplug USB to boot normally.
- Recovery ADB has its **own** auth prompt — tap **Allow** (not No).
- Internal **nexmon** (V0lk3n's 23.0 module) does **not** work on 23.2 (`__nex_driver_io: error`, firmware mismatch) — use the ALFA.

## Optional extras
- **PlayIntegrityFix** — so Google Play / banking apps pass integrity checks (needs Zygisk).
- **Magisk Overlayfs** — systemless writable `/system`; rarely needed.
- **Splash screen** — removes the unlocked-bootloader boot warning (cosmetic).

Sources: [Kali S10 guide](https://www.kali.org/docs/nethunter/installing-nethunter-on-the-samsung-galaxy-s10/) · [V0lk3n kernel](https://github.com/V0lk3n/nethunter_kernel_samsung_exynos9820) · [get-kali](https://www.kali.org/get-kali/) · [Magisk](https://github.com/topjohnwu/Magisk/releases).
