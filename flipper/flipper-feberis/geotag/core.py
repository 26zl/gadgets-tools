#!/usr/bin/env python3
"""Geotag Flipper captures against a GPX track."""
import argparse
import bisect
import csv
import io
import json
import math
import os
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

CAPTURE_EXTS = {".sub", ".nfc", ".rfid", ".ir", ".bin"}
EPOCH_MAX = 4102444800   # 2100-01-01 UTC


def _local(tag):
    """Strip any XML namespace: '{ns}trkpt' -> 'trkpt'."""
    return tag.rsplit("}", 1)[-1]


def parse_time(s):
    """Parse a GPX <time> to int epoch seconds, or None. Tolerates Z, offsets, fractional secs."""
    s = re.sub(r"\.\d+", "", s.strip())          # drop fractional seconds; whole seconds only
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        return None
    if dt.tzinfo is None:                         # no zone -> assume UTC (GPX is UTC by spec)
        dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp())


def parse_gpx(path):
    """Return [(epoch, lat, lng), ...] sorted by time; skip bad points, reject DTD/entity decls (XXE guard)."""
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except OSError as e:
        sys.exit(f"cannot read GPX {path}: {e}")
    if b"<!DOCTYPE" in data or b"<!ENTITY" in data:
        sys.exit(f"refusing {path}: XML DTD/entity declarations are not allowed")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as e:
        sys.exit(f"cannot parse GPX {path}: {e}")
    pts = []
    for tp in root.iter():
        if _local(tp.tag) != "trkpt":
            continue
        lat, lon = tp.get("lat"), tp.get("lon")
        t = next((c.text for c in tp if _local(c.tag) == "time"), None)
        if lat is None or lon is None or not t:
            continue
        epoch = parse_time(t)
        if epoch is None:
            continue
        try:
            la, lo = float(lat), float(lon)
        except ValueError:
            continue
        if not (math.isfinite(la) and math.isfinite(lo) and -90 <= la <= 90 and -180 <= lo <= 180):
            continue
        pts.append((epoch, la, lo))
    pts.sort()
    return pts


def nearest(times, t):
    """Index into sorted `times` of the entry closest to t (None if empty)."""
    if not times:
        return None
    i = bisect.bisect_left(times, t)
    if i == 0:
        return 0
    if i == len(times):
        return len(times) - 1
    return i if (times[i] - t) < (t - times[i - 1]) else i - 1


def geotag(track, captures, tol):
    """captures: [(name, type, epoch)]. Returns rows joined to nearest track point within tol."""
    times = [p[0] for p in track]
    rows = []
    for name, typ, cap_t in captures:
        i = nearest(times, cap_t)
        if i is not None and abs(track[i][0] - cap_t) <= tol:
            rows.append((name, typ, cap_t, track[i][1], track[i][2], True))
        else:
            rows.append((name, typ, cap_t, None, None, False))
    return rows


def collect_captures(root, offset):
    """Walk `root` deterministically; identify captures by path relative to root (not basename)."""
    out = []
    for dirpath, dirs, files in os.walk(root):
        dirs.sort()
        for f in sorted(files):
            ext = os.path.splitext(f)[1].lower()
            if ext not in CAPTURE_EXTS:
                continue
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, root)
            out.append((rel, ext.lstrip("."), int(os.path.getmtime(p)) + offset))
    return out


def csvsafe(v):
    """Neutralize CSV/formula injection: prefix a leading =, +, -, @ etc. with an apostrophe."""
    s = str(v)
    return "'" + s if s.lstrip(" ")[:1] in ("=", "+", "-", "@", "\t", "\r") else s


def _iso(t):
    return datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _write_temp(path, text):
    """Write owner-only text to a synced temporary file."""
    tmp = f"{path}.{os.getpid()}.tmp"                     # pid keeps concurrent runs from colliding
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", newline="") as fh:
        fh.write(text)
        fh.flush()
        os.fsync(fh.fileno())
    return tmp


def write_outputs(rows, out):
    csv_path, gj_path = out + ".csv", out + ".geojson"
    # Prepare both outputs before replacing existing files.
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["file", "type", "capture_utc", "lat", "lng", "matched"])
    for name, typ, t, lat, lng, ok in rows:
        w.writerow([csvsafe(name), csvsafe(typ), _iso(t),
                    "" if lat is None else lat, "" if lng is None else lng, ok])
    feats = [{
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [lng, lat]},
        "properties": {"file": name, "type": typ, "capture_utc": _iso(t)},
    } for name, typ, t, lat, lng, ok in rows if ok]
    gj = json.dumps({"type": "FeatureCollection", "features": feats}, indent=1)

    csv_tmp = _write_temp(csv_path, buf.getvalue())
    try:
        gj_tmp = _write_temp(gj_path, gj)
    except BaseException:
        os.unlink(csv_tmp)
        raise
    os.replace(csv_tmp, csv_path)
    try:
        os.replace(gj_tmp, gj_path)
    except BaseException:
        os.unlink(gj_tmp)                                 # csv already committed; don't leak the temp
        raise


def main(argv=None):
    ap = argparse.ArgumentParser(prog="geotag", description="Geotag Flipper captures against a GPX track.")
    ap.add_argument("gpx")
    ap.add_argument("captures")
    ap.add_argument("--tol", type=int, default=30, help="max seconds between capture and track point")
    ap.add_argument("--offset", type=int, default=0, help="seconds to add to capture times (RTC skew fix)")
    ap.add_argument("--out", default="geotagged")
    a = ap.parse_args(argv)

    if not os.path.isfile(a.gpx):
        sys.exit(f"no such GPX file: {a.gpx}")
    if not os.path.isdir(a.captures):
        sys.exit(f"no such capture directory: {a.captures}")
    if a.tol < 0:
        sys.exit("--tol must be >= 0")

    track = parse_gpx(a.gpx)
    if not track:
        sys.exit("no valid timestamped track points in " + a.gpx)
    caps = collect_captures(a.captures, a.offset)
    if not caps:
        print(f"warning: no capture files ({', '.join(sorted(CAPTURE_EXTS))}) under {a.captures}",
              file=sys.stderr)
    if any(not (0 <= t <= EPOCH_MAX) for _, _, t in caps):
        sys.exit("--offset produces out-of-range capture times; check the value")

    rows = geotag(track, caps, a.tol)
    write_outputs(rows, a.out)
    matched = sum(1 for r in rows if r[5])
    print(f"{matched}/{len(rows)} captures matched -> {a.out}.csv, {a.out}.geojson")


if __name__ == "__main__":
    main()
