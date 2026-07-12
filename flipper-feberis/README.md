# Flipper Zero + Feberis Pro tools

Two tools for the Flipper Zero + Feberis Pro:

| Component | What it does |
| --- | --- |
| `platformio.ini`, `src/` | ESP32 firmware: own WiFi AP + offline web dashboard, live WiFi scan, GPS, a live moving-map view, and WiGLE CSV / GPX downloads to your phone. |
| `geotag/` | Desktop tool that joins Flipper captures to GPS positions by timestamp. |

The dashboard works offline over its own access point, and its GPX track feeds the geotag tool.

> **Use it ethically.** Only scan, capture from, or test networks and devices you own or are
> explicitly authorized to assess. Wardriving and RF-capture laws vary by country.

---

## Firmware (ESP32)

- live GPS fix + satellite count, buffer usage, free heap, scan state
- live list of APs by signal strength + offline scatter "map"
- **WiGLE CSV** download (upload to wigle.net, or view later on a real map)
- **GPX** track download (feeds the geotag tool)

The track stores about 1000 points and downsamples automatically while displaying its current interval.

### Build

```bash
pio run          # -> .pio/build/esp32dev/{firmware,bootloader,partitions}.bin
```

Open the `flipper-feberis/` folder directly in PlatformIO — `platformio.ini` is here.

The platform and library versions are pinned in `platformio.ini` for reproducible builds.

### Flash

**Over USB (simplest):**

```bash
pio run -t upload
```

**Via the Flipper (ESP Flasher):** copy these four files to the SD card, flash them at the listed
offsets, and power-cycle:

| File | Offset | Location |
| --- | --- | --- |
| `bootloader.bin` | `0x1000` | `.pio/build/esp32dev/` |
| `partitions.bin` | `0x8000` | `.pio/build/esp32dev/` |
| `boot_app0.bin` | `0xE000` | `~/.platformio/packages/framework-arduinoespressif32/tools/partitions/boot_app0.bin` |
| `firmware.bin` | `0x10000` | `.pio/build/esp32dev/` |

`boot_app0.bin` ships with the Arduino framework, not in the build output — copy it from the path
above. Set the Feberis switch to **ESP32 + GPS** mode.

### Use

1. Connect the ESP32 over USB and open the serial monitor at 115200. On boot it prints the AP
   password — note it once.
2. On your phone, join the hidden WiFi **`FeberisRecon`** (add it manually as a network) with that password.
3. Open `http://192.168.4.1`. Walk/drive around; download the CSV/GPX when done.

Change the SSID/pins at the top of `src/main.cpp`.

### Security & privacy

- **The AP password is random**, generated on first boot and stored in the ESP32's NVS — it is not
  derived from anything broadcast and not in this repo. It is reprinted to serial on every boot.
- To set a **fixed** password instead, uncomment `build_flags` in `platformio.ini`
  (`-DFEBERIS_AP_PASS='"your-8-to-63-char-password"'`) and rebuild.
- **The AP is hidden and endpoints are not individually authenticated** — the WPA2 password *is*
  the access control. Anyone with it (i.e. on the AP) can download `/track.gpx`, your movement
  history; a per-endpoint token served over that same AP would add no real protection. Treat the
  password as a secret and don't run the AP when you don't need it.

---

## geotag

After a session you have a GPX track (from the firmware) and Flipper captures on the SD card:

Run from `flipper-feberis/`:

```bash
python3 -m geotag TRACK.gpx /path/to/flipper/subghz --tol 30 --out session
# -> session.csv and session.geojson  (written atomically, 0600)
```

- capture time = each file's modification time (the Flipper's RTC sets it on save), so read files
  **straight from the SD card** or copy with `cp -p` — a normal copy can reset mtimes;
- `--offset <seconds>` corrects a known Flipper-clock skew;
- `--tol` is how many seconds a capture may be from a track point before it's left unmatched.

Pure Python stdlib, offline. **Note:** `session.geojson` on geojson.io and `session.csv` on wigle.net
upload your locations, filenames, SSIDs and BSSIDs to those third parties — keep them local if that
matters.

---

## Tests

```bash
python3 -m unittest discover                                                     # geotag logic
c++ -std=c++17 -O2 tests/date_math_test.cpp -o /tmp/dt && /tmp/dt                 # firmware date math vs timegm
c++ -std=c++17 -O2 tests/track_test.cpp -o /tmp/tk && /tmp/tk                     # firmware track decimation
c++ -std=c++17 -O2 tests/format_test.cpp -o /tmp/fmt && /tmp/fmt                  # CSV/JSON escaping (injection + UTF-8)
```

CI (`.github/workflows/ci.yml`) also runs a firmware build on every push.

---

## Hardware acceptance test (before field use)

Firmware behaviour that can only be confirmed on a real Feberis Pro — run through this once:

- [ ] Flashes and boots; serial prints the AP; password is stable across reboots.
- [ ] GPS locks (UART on GPIO4/13, 9600 baud); `fix`/`sats` update; losing signal flips to "no fix".
- [ ] AP stays reachable during WiFi scans; dashboard keeps updating.
- [ ] Multi-hour run: free heap stabilizes, no reset; note dropped-AP count in a dense area.
- [ ] Download CSV + GPX while scanning; GPS keeps updating during the download.
- [ ] WiGLE CSV imports on wigle.net; GPX opens in a mapping tool.

---

MIT licensed — see [LICENSE](../LICENSE).
