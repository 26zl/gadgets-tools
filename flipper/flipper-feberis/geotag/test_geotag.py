"""Unit tests for geotag.core."""
import calendar
import contextlib
import csv
import io
import json
import os
import stat
import tempfile
import unittest

import geotag.core as gt


class TestJoin(unittest.TestCase):
    def test_nearest_within_tolerance(self):
        track = [(100, 59.0, 10.0), (110, 59.1, 10.1), (120, 59.2, 10.2)]
        caps = [("a.sub", "sub", 108), ("b.sub", "sub", 130), ("c.nfc", "nfc", 100)]
        rows = gt.geotag(track, caps, tol=6)
        self.assertEqual(rows[0][3:], (59.1, 10.1, True))   # 108 -> 110 (diff 2)
        self.assertFalse(rows[1][5])                         # 130 -> 120 (diff 10 > 6)
        self.assertEqual(rows[2][3:], (59.0, 10.0, True))    # exact hit

    def test_nearest_edges(self):
        self.assertIsNone(gt.nearest([], 5))
        self.assertEqual(gt.nearest([10], 999), 0)


class TestTime(unittest.TestCase):
    def test_offset_and_fractional(self):
        self.assertEqual(gt.parse_time("2026-07-01T12:00:01.5+02:00"),
                         gt.parse_time("2026-07-01T10:00:01Z"))

    def test_absolute(self):
        self.assertEqual(gt.parse_time("2026-07-01T00:00:00Z"),
                         calendar.timegm((2026, 7, 1, 0, 0, 0, 0, 0, 0)))

    def test_reject(self):
        self.assertIsNone(gt.parse_time("bogus"))

    def test_naive_assumed_utc(self):
        self.assertEqual(gt.parse_time("2026-07-01T00:00:00"),      # no zone -> UTC per GPX spec
                         gt.parse_time("2026-07-01T00:00:00Z"))


class TestParseGpx(unittest.TestCase):
    def _parse(self, gpx):
        fd, p = tempfile.mkstemp(suffix=".gpx")
        os.write(fd, gpx.encode())
        os.close(fd)
        try:
            return gt.parse_gpx(p)
        finally:
            os.unlink(p)

    def test_skips_bad_points(self):
        pts = self._parse(
            "<gpx><trk><trkseg>"
            '<trkpt lat="1.0" lon="2.0"><time>2026-07-01T12:00:00Z</time></trkpt>'
            '<trkpt lat="3.0" lon="4.0"><time>2026-07-01T12:00:01.500+02:00</time></trkpt>'
            '<trkpt lat="5.0" lon="6.0"><time>bogus</time></trkpt>'      # bad time
            '<trkpt lat="7.0" lon="8.0"></trkpt>'                        # no time
            '<trkpt lat="91.0" lon="6.0"><time>2026-07-01T12:00:03Z</time></trkpt>'  # lat out of range
            "</trkseg></trk></gpx>")
        self.assertEqual({q[1:] for q in pts}, {(1.0, 2.0), (3.0, 4.0)})
        self.assertEqual(pts[0][0], gt.parse_time("2026-07-01T10:00:01Z"))  # offset sorts first

    def test_namespaced(self):
        pts = self._parse(
            '<gpx xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>'
            '<trkpt lat="1.0" lon="2.0"><time>2026-07-01T12:00:00Z</time></trkpt>'
            "</trkseg></trk></gpx>")
        self.assertEqual(len(pts), 1)

    def test_rejects_dtd(self):                       # XXE / billion-laughs guard
        with self.assertRaises(SystemExit):
            self._parse('<!DOCTYPE r [<!ENTITY x "y">]><gpx>&x;</gpx>')

    def test_skips_nonfinite_and_nonnumeric(self):
        pts = self._parse(
            "<gpx><trk><trkseg>"
            '<trkpt lat="inf" lon="10.0"><time>2026-07-01T12:00:00Z</time></trkpt>'   # non-finite
            '<trkpt lat="abc" lon="10.0"><time>2026-07-01T12:00:01Z</time></trkpt>'   # non-numeric
            '<trkpt lat="90.0" lon="180.0"><time>2026-07-01T12:00:02Z</time></trkpt>' # inclusive bound
            "</trkseg></trk></gpx>")
        self.assertEqual({q[1:] for q in pts}, {(90.0, 180.0)})


class TestCsvSafe(unittest.TestCase):
    def test_escapes_formula(self):
        self.assertEqual(gt.csvsafe("=cmd()"), "'=cmd()")
        self.assertEqual(gt.csvsafe("home.sub"), "home.sub")
        self.assertEqual(gt.csvsafe(" =cmd()"), "' =cmd()")     # formula after leading space
        self.assertEqual(gt.csvsafe("\t=x"), "'\t=x")           # leading tab


class TestCollect(unittest.TestCase):
    def test_relpath_and_determinism(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "b"))
            os.makedirs(os.path.join(d, "a"))
            for rel in ("a/x.sub", "b/x.sub", "ignore.txt"):
                with open(os.path.join(d, rel), "w") as fh:
                    fh.write("x")
            names = [c[0] for c in gt.collect_captures(d, 0)]
            self.assertEqual(names, [os.path.join("a", "x.sub"), os.path.join("b", "x.sub")])


class TestOutputs(unittest.TestCase):
    def test_geojson_and_mode(self):
        rows = [("a.sub", "sub", 100, 59.0, 10.0, True),
                ("b.sub", "sub", 130, None, None, False)]
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "res")
            gt.write_outputs(rows, out)
            with open(out + ".geojson") as fh:
                gj = json.load(fh)
            self.assertEqual(len(gj["features"]), 1)                      # only the matched row
            self.assertEqual(gj["features"][0]["geometry"]["coordinates"], [10.0, 59.0])
            if os.name == "posix":
                self.assertEqual(stat.S_IMODE(os.stat(out + ".csv").st_mode), 0o600)
                self.assertEqual(stat.S_IMODE(os.stat(out + ".geojson").st_mode), 0o600)


class TestMainEndToEnd(unittest.TestCase):
    def test_csv_content(self):
        with tempfile.TemporaryDirectory() as d:
            gpx = os.path.join(d, "t.gpx")
            with open(gpx, "w") as fh:
                fh.write('<gpx xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>'
                         '<trkpt lat="59.0" lon="10.0"><time>2026-07-01T12:00:00Z</time></trkpt>'
                         '<trkpt lat="59.5" lon="10.5"><time>2026-07-01T12:01:00Z</time></trkpt>'
                         "</trkseg></trk></gpx>")
            caps = os.path.join(d, "caps")
            os.makedirs(caps)
            sub = os.path.join(caps, "door.sub")
            with open(sub, "w") as fh:
                fh.write("x")
            t = calendar.timegm((2026, 7, 1, 12, 0, 5, 0, 0, 0))   # 5 s after the first trkpt
            os.utime(sub, (t, t))
            out = os.path.join(d, "res")
            gt.main([gpx, caps, "--tol", "30", "--out", out])
            with open(out + ".csv", newline="") as fh:
                rows = list(csv.reader(fh))
        self.assertEqual(rows[0], ["file", "type", "capture_utc", "lat", "lng", "matched"])
        self.assertEqual(rows[1], ["door.sub", "sub", "2026-07-01T12:00:05Z", "59.0", "10.0", "True"])
        self.assertEqual(len(rows), 2)                          # header + the one capture

    def test_offset_brings_into_tolerance(self):
        with tempfile.TemporaryDirectory() as d:
            gpx = os.path.join(d, "t.gpx")
            with open(gpx, "w") as fh:
                fh.write('<gpx xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>'
                         '<trkpt lat="59.0" lon="10.0"><time>2026-07-01T12:00:00Z</time></trkpt>'
                         "</trkseg></trk></gpx>")
            caps = os.path.join(d, "caps")
            os.makedirs(caps)
            sub = os.path.join(caps, "x.sub")
            with open(sub, "w") as fh:
                fh.write("x")
            t0 = calendar.timegm((2026, 7, 1, 12, 0, 0, 0, 0, 0))
            os.utime(sub, (t0 - 100, t0 - 100))                # 100 s before the track point
            out = os.path.join(d, "res")
            gt.main([gpx, caps, "--tol", "30", "--offset", "100", "--out", out])   # +100 s cancels it out
            with open(out + ".csv", newline="") as fh:
                row = list(csv.reader(fh))[1]
            self.assertEqual(row[5], "True")


class TestMainErrors(unittest.TestCase):
    def setUp(self):
        td = tempfile.TemporaryDirectory()
        self.addCleanup(td.cleanup)
        self.d = td.name
        self.gpx = os.path.join(self.d, "t.gpx")
        with open(self.gpx, "w") as fh:
            fh.write('<gpx xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>'
                     '<trkpt lat="59.0" lon="10.0"><time>2026-07-01T12:00:00Z</time></trkpt>'
                     "</trkseg></trk></gpx>")
        self.caps = os.path.join(self.d, "caps")
        os.makedirs(self.caps)
        self.out = os.path.join(self.d, "res")

    def test_missing_gpx(self):
        with self.assertRaises(SystemExit):
            gt.main([os.path.join(self.d, "nope.gpx"), self.caps, "--out", self.out])

    def test_missing_capture_dir(self):
        with self.assertRaises(SystemExit):
            gt.main([self.gpx, os.path.join(self.d, "nope"), "--out", self.out])

    def test_negative_tol(self):
        with self.assertRaises(SystemExit):
            gt.main([self.gpx, self.caps, "--tol", "-1", "--out", self.out])

    def test_empty_track(self):
        bad = os.path.join(self.d, "bad.gpx")
        with open(bad, "w") as fh:
            fh.write("<gpx><trk><trkseg>"
                     '<trkpt lat="1.0" lon="2.0"><time>bogus</time></trkpt>'
                     "</trkseg></trk></gpx>")
        with self.assertRaises(SystemExit):
            gt.main([bad, self.caps, "--out", self.out])

    def test_offset_out_of_range(self):
        with open(os.path.join(self.caps, "x.sub"), "w") as fh:
            fh.write("x")
        with self.assertRaises(SystemExit):                    # mtime - EPOCH_MAX goes negative
            gt.main([self.gpx, self.caps, "--offset", str(-gt.EPOCH_MAX), "--out", self.out])

    def test_no_captures_warns_not_exit(self):
        err = io.StringIO()
        with contextlib.redirect_stderr(err):                  # empty caps dir: warn, don't exit
            gt.main([self.gpx, self.caps, "--out", self.out])
        self.assertIn("no capture files", err.getvalue())
        with open(self.out + ".csv", newline="") as fh:
            self.assertEqual(len(list(csv.reader(fh))), 1)     # header only


if __name__ == "__main__":
    unittest.main()
