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
| Google | **none — de-Googled** (no Play Services / Play Store); Aurora Store for apps, microG optional |

## Magisk version

The [official Kali S10 guide](https://www.kali.org/docs/nethunter/installing-nethunter-on-the-samsung-galaxy-s10/) says Magisk **v28.1** — that is too old for Android 16 and **bootloops**. Use **Magisk v30.7+**.

## Tools

**Host (macOS / Linux / WSL):**

- **adb** (Android platform-tools) — macOS `brew install android-platform-tools` · Debian/Ubuntu/WSL `sudo apt install adb`
- **Heimdall** — macOS `sudo port install Heimdall` (MacPorts; Homebrew's formula + cask are dead) · Debian/Ubuntu/WSL `sudo apt install heimdall-flash`
- `gh` (GitHub CLI) · `curl` · `python3`

> **WSL:** wireless adb (`adb pair` / `adb connect`) works out of the box, so the day-to-day provisioning (`apps.sh`, `setup.sh`, `sdcard.sh`, …) runs fine. Only the reinstall's USB steps (Heimdall flash, USB adb) need the phone attached to WSL via [usbipd-win](https://github.com/dorssel/usbipd-win) — or run those from Windows.

**Hardware:**

- ALFA Network **AWUS036ACS** (RTL8811AU) — external dual-band WiFi, monitor/injection
- HiLetgo **VK172** (u-blox 7) — USB GPS/GNSS receiver
- **Belkin USB-C hub — must be powered** (PD input / powerbank). It runs the ALFA + GPS together off the phone's single USB-C port, but the ALFA is power-hungry on TX: on bus power alone, **injection browns out the whole hub** (ALFA + GPS drop out, then a ~7 s USB reconnect loop). Monitor/RX works unpowered; **injection needs the hub powered** — with a powerbank it hits ~96% ACK.

## Scripts (in [`scripts/`](scripts/))

| Script | Does |
| --- | --- |
| `upgrade.sh` | Guided (re)install — downloads + walks you through every step, then verifies |
| `prepare-upgrade.sh` | Just download the latest files → `~/nethunter-s10` |
| `setup.sh` | **Post-install provisioning** — installs the chroot tools/deps not in the base image (nmap, gpsd, aircrack/wifite, pipx …), ships the bundled tools + `phone-doctor.sh`, then verifies |
| `verify.sh` | adb health-check from the **Mac** (device, kernel, Magisk, NetHunter apps) |
| `phone-doctor.sh` | health check run **on the phone** as root (AndroidSu / Termux): chroot, ALFA, GPS, netsec-auditor |
| `apps.sh` | install the full Android app set via adb (stores, terminal, firewall/DNS, browser, tools) |
| `magisk-modules.sh` | stage the Magisk module zips (LSPosed/Vector, Shamiko, PIF, ReZygisk) → `/sdcard/Download` |
| `sdcard.sh` | shuttle files to the microSD to save internal storage — `info` / `push` / `move` |
| `extras.sh` | install non-cybersec apps — media/torrent, dev/sysadmin, daily (FOSS-first) |
| `ssh-setup.sh` | key-only SSH into the Kali chroot — runs as **root** (reachable past a per-app VPN; auto-starts on boot via Magisk `service.d`). Stable alternative to wireless adb for Kali work; Android app-management (`pm`/`am`) still via adb |

## Bundled tools (submodules)

My own tools that run on the phone, pulled in as submodules (`git submodule update --init --recursive`):

| Submodule | What |
| --- | --- |
| [`netsec-auditor/`](netsec-auditor/) | Scope-gated network / OT-ICS / IoT / Wi-Fi auditor (Python CLI, JSON/HTML/PDF reports) |
| [`cybersec-toolkit/`](cybersec-toolkit/) | Modular installer for 580+ security tools (Linux + Termux) + an MCP server |

**Running `netsec-auditor` in the chroot.** Install it straight in the Kali terminal (see netsec-auditor's own README for the full guide):

```bash
apt install -y nmap pipx bluez
git clone https://github.com/26zl/netsec-auditor.git && cd netsec-auditor
pipx install ".[wireless]"        # ".[all]" adds BLE + PDF
netsec-auditor doctor
```

No network in the chroot? Ship the source over adb instead:

```bash
git -C netsec-auditor archive HEAD -o /tmp/na.tar
adb push /tmp/na.tar /data/local/tmp/
adb shell su -c 'K=/data/local/nhsystem/kali-arm64; mkdir -p $K/root/na; tar xf /data/local/tmp/na.tar -C $K/root/na; \
  chroot $K /bin/bash -lc "cd /root/na && pip install --break-system-packages . && netsec-auditor doctor"'
```

Verified on the S10: `doctor` green (root/privileged, nmap, scapy, cryptography), a LAN `discover` found live hosts. Optional extras (`bleak`/BLE, `weasyprint`/PDF, `masscan`) aren't installed by default.

## What's on the phone

### Android apps (`./scripts/apps.sh`)

Installed via adb from official sources (GitHub / GitLab / F-Droid).

| Category | Apps |
| --- | --- |
| App stores | [F-Droid](https://f-droid.org) · [Droid-ify](https://github.com/Droid-ify/client) · [Aurora Store](https://gitlab.com/AuroraOSS/AuroraStore) (anon Play) · [Obtainium](https://github.com/ImranR98/Obtainium) (GitHub-release installer) |
| Terminal | [Termux](https://github.com/termux/termux-app) + [Termux:API](https://github.com/termux/termux-api) + [Termux:Boot](https://github.com/termux/termux-boot) |
| Network / privacy | [AdAway](https://github.com/AdAway/AdAway) (systemless hosts) · [Mullvad VPN](https://github.com/mullvad/mullvadvpn-app) · [PCAPdroid](https://github.com/emanuele-f/PCAPdroid) (packet capture) · [WiGLE WiFi](https://github.com/wiglenet/wigle-wifi-wardriving) (wardriving / GPS logging) |
| Browser | [Cromite](https://github.com/uazo/cromite) (hardened Chromium; [IronFox](https://gitlab.com/ironfox-oss/IronFox) = hardened Firefox alt) |
| Files / apps / cleanup | [Material Files](https://github.com/zhanghai/MaterialFiles) (root file mgr) · [App Manager](https://github.com/MuntashirAkon/AppManager) · [SD Maid SE](https://github.com/d4rken-org/sdmaid-se) |
| Root manager | [Magisk](https://github.com/topjohnwu/Magisk) (from the base install) |

> **Termux** (+ API/Boot) installs from **GitHub only** for the latest build — the three share one `com.termux` signature, so `apps.sh` never mixes sources. Only ever update Termux from its official GitHub releases (that build is signed with a shared community test key).

**Add your own apps:** in `apps.sh` append a line to the `GH_APPS` array — `pkgid|Label|owner/repo|apk-glob`. In `extras.sh` call `fdroid <pkgid> "Label"` (F-Droid) or `ghub <pkgid> "Label" <owner/repo> "<glob>"` (GitHub). One line per app.

### Magisk modules (`./scripts/magisk-modules.sh` → staged to `/sdcard/Download`)

Can't be adb-installed — install in **Magisk → Modules → Install from storage → reboot**. Enable **Zygisk** first; add banking/sensitive apps to the **DenyList** (Shamiko enforces the hiding).

> **Optional — this build is de-Googled** (no Play Services / Store). **PlayIntegrityFork/ReZygisk are a no-op without Google** — they only do anything if you add **microG** or GApps. LSPosed (Xposed) works regardless.

| Module | Purpose |
| --- | --- |
| [LSPosed (Vector)](https://github.com/JingMatrix/LSPosed) | Xposed framework, Android 16 fork |
| [Shamiko](https://github.com/LSPosed/LSPosed.github.io/releases) | hide root from detection |
| [PlayIntegrityFork (PIF)](https://github.com/osm0sis/PlayIntegrityFork) | pass Play Integrity — **only with Google/microG** (no-op on this de-Googled build) |
| [ReZygisk](https://github.com/PerformanC/ReZygisk) | stronger Zygisk implementation — if used, **disable Magisk's built-in Zygisk** |

> Basic/Device integrity works for most apps; **Strong** (hardware-backed) integrity needs TrickyStore + a keybox — advanced and a moving target.

### Kali chroot (`./scripts/setup.sh` + `kalifs_full`)

Base image ships `nmap` · aircrack-ng suite · `wifite` · `reaver` · `kismet` · `bettercap` · `gpsd`. `setup.sh` adds `masscan` · `pipx` · `gpsd-clients` and installs **netsec-auditor**. Health-check the whole rig with `scripts/phone-doctor.sh`.

> **Upgrading the chroot:** systemd v260+ can't configure on this device's 4.14 kernel ([systemd #41250](https://github.com/systemd/systemd/issues/41250) — `openat2` unsupported → `Protocol driver not attached`), so the systemd stack is **held** (`apt-mark hold systemd systemd-sysv udev libsystemd0 libpam-systemd`) to keep `dpkg` consistent. Run big upgrades with `TMPDIR=/tmp` and a `policy-rc.d` returning `101` (standard chroot practice — blocks service starts) to avoid `mktemp` / service-start failures.

### Hardening applied

- **Private DNS** → `base.dns.mullvad.net` ([Mullvad DoT](https://mullvad.net/en/help/dns-over-https-and-dns-over-tls) — blocks ads/trackers/malware), set via `settings put global private_dns_mode hostname` + `private_dns_specifier`.
- Ad/tracker/malware blocking is handled at the DNS layer by Mullvad Private DNS (above); app-permission review is up to you. No app-firewall is installed.

### Daily / non-cybersec apps (`./scripts/extras.sh`)

| Category | Apps |
| --- | --- |
| Media / torrent | [LibreTorrent](https://github.com/proninyaroslav/libretorrent) · [LibreTube](https://github.com/libre-tube/LibreTube) · [AntennaPod](https://github.com/AntennaPod/AntennaPod) · [VLC](https://www.videolan.org/vlc/)\* · [Stremio](https://www.stremio.com)\* |
| Dev / sysadmin | [Acode](https://github.com/Acode-Foundation/Acode) (editor) · [ConnectBot](https://github.com/connectbot/connectbot) (SSH) · [RustDesk](https://github.com/rustdesk/rustdesk) (remote desktop) · [WireGuard](https://www.wireguard.com)\* · [Termux](https://github.com/termux/termux-app) |
| Daily / general | [Aegis](https://github.com/beemdevelopment/Aegis) (2FA) · [KeePassDX](https://github.com/Kunzisoft/KeePassDX) (passwords) · [Organic Maps](https://github.com/organicmaps/organicmaps) · [Joplin](https://joplinapp.org) (notes) · [Breezy Weather](https://github.com/breezy-weather/breezy-weather) · [KOReader](https://github.com/koreader/koreader) (ebooks) |

*\* VLC / WireGuard = one tap in F-Droid (multi-abi builds); Stremio from [stremio.com](https://www.stremio.com) (torrent streaming via the Torrentio addon). Dev shell = Termux: `pkg install nodejs python go rust git neovim tmux openssh`.*

## Install / upgrade

**Easiest:** `./scripts/upgrade.sh` — run it interactively (the `vbmeta` / `setenforce` steps need a local shell). Or manually:

1. **Recovery + AVB off** (Download mode):

   ```bash
   heimdall flash --RECOVERY recovery.img --VBMETA vbmeta.img --no-reboot
   ```

2. **ROM**: boot recovery → Format everything → `adb -d sideload lineage-23.2-*.zip`
   *(or LineageOS Updater in-place — but it re-enables AVB, so re-flash the disabling `vbmeta` before rooting)*
3. **Root**: install **Magisk v30.7** → *Install → Select and Patch a File → `boot.img`* → `heimdall flash --BOOT magisk_patched.img`
4. **NetHunter**: `adb push kali-nethunter-*-full.zip /sdcard/` → Magisk → Modules → Install from Storage → reboot
5. `./scripts/verify.sh`
6. `./scripts/setup.sh` — provision the userspace tools + bundled tools + on-device `phone-doctor.sh`

## Peripherals — setup

### Cable-free adb (frees USB-C for the hub)

Developer options → **Wireless debugging**, then on the host:

```bash
adb pair <ip>:<pairPort> <code>      # from "Pair device with pairing code"
adb connect <ip>:<connectPort>       # main screen — a DIFFERENT port, changes on every WiFi reconnect
```

### External WiFi — ALFA → `wlan2`

Driver is built into the NetHunter kernel; the ALFA shows up as `wlan2` over the hub. **Power the hub first** — injection browns out an unpowered one (see Hardware). In the **Kali terminal**:

```bash
airmon-ng check kill
airmon-ng start wlan2          # stays wlan2 (not wlan2mon)
aireplay-ng --test wlan2       # -> "Injection is working!"
wifite -i wlan2
```

> `airmon-ng check kill` kills the phone's WiFi → **wireless adb drops**. Do host/adb work first.

With SELinux **permissive** (`setenforce 0`), `iw`/`ip`/`aireplay-ng` are native (`/system/bin`) and run straight from `adb shell su` — no chroot. Touch only `wlan2` (skip `check kill`) and wireless adb stays up:

```bash
adb shell su -c 'ip link set wlan2 down; iw dev wlan2 set type monitor; ip link set wlan2 up'
adb shell su -c 'aireplay-ng --test wlan2'    # -> "Injection is working!"
```

### GPS — VK172 → `gpsd`

Appears as `/dev/ttyACM0` (cdc_acm, built-in) and streams NMEA. In the **Kali terminal**:

```bash
gpsd -n /dev/ttyACM0
cgps                           # wait for 3D fix (needs sky view; cold start ~1 min)
airodump-ng --gpsd -w wardrive wlan2
```

Or NetHunter app → **Wardriving** (or the [WiGLE](https://github.com/wiglenet/wigle-wifi-wardriving) app).

## Gotchas

- **Magisk v28.1 bootloops on A16** → v30.7+.
- A Magisk-patched boot needs **AVB disabled** (`vbmeta`); the LineageOS Updater **re-enables** it.
- `--VBMETA` flash and `setenforce 0` weaken security — run them manually.
- USB plugged in during a force-reboot → Samsung jumps to Download mode. Unplug USB to boot normally.
- Recovery ADB has its **own** auth prompt — tap **Allow** (not No).
- Internal **nexmon** (V0lk3n's 23.0 module) does **not** work on 23.2 (`__nex_driver_io: error`, firmware mismatch) — use the ALFA.

## Optional extras

- **Magisk Overlayfs** — systemless writable `/system`; rarely needed.
- **Splash screen** — removes the unlocked-bootloader boot warning (cosmetic).

Sources: [Kali S10 guide](https://www.kali.org/docs/nethunter/installing-nethunter-on-the-samsung-galaxy-s10/) · [V0lk3n kernel](https://github.com/V0lk3n/nethunter_kernel_samsung_exynos9820) · [get-kali](https://www.kali.org/get-kali/) · [Magisk](https://github.com/topjohnwu/Magisk/releases).
