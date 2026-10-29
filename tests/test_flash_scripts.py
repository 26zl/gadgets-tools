import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIRMWARE = b"synthetic firmware fixture\n"
BOOT = b"synthetic boot fixture\n"


class FlashSafetyTests(unittest.TestCase):
    def run_flash(self, device, *, reply="y\n", failure=""):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            mock_bin = work / "bin"
            mock_bin.mkdir()
            log = work / "calls"
            source = (ROOT / device / "flash.sh").read_text()
            for name, content in (("ASSET_SHA256", FIRMWARE), ("BOOT_APP0_SHA256", BOOT)):
                source = re.sub(
                    rf'^{name}="[a-f0-9]+"$',
                    f'{name}="{hashlib.sha256(content).hexdigest()}"',
                    source,
                    flags=re.MULTILINE,
                )
            script = work / "flash.sh"
            script.write_text(source)
            mock = f"#!{sys.executable}\n" + '''import os
from pathlib import Path
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
failure = os.environ.get("FLASH_TEST_FAILURE", "")
with open(os.environ["FLASH_TEST_LOG"], "a") as log:
    log.write(name + " " + " ".join(args) + "\\n")
if name == "gh":
    if failure == "download":
        sys.exit(1)
    asset = args[args.index("--pattern") + 1]
    destination = Path(args[args.index("--dir") + 1]) / asset
    destination.write_bytes(b"corrupt" if failure == "firmware" else b"synthetic firmware fixture\\n")
elif name == "curl":
    destination = Path(args[args.index("-o") + 1])
    destination.write_bytes(b"corrupt" if failure == "boot" else b"synthetic boot fixture\\n")
elif name == "unzip":
    if failure == "archive":
        sys.exit(1)
    destination = Path(args[args.index("-d") + 1])
    for filename in ("bootloader.bin", "partitions.bin", "firmware.bin"):
        (destination / filename).write_bytes(b"synthetic extracted image")
elif name == "esptool.py" and failure == "flash":
    sys.exit(1)
'''
            for name in ("gh", "curl", "unzip", "esptool.py"):
                executable = mock_bin / name
                executable.write_text(mock)
                executable.chmod(0o700)
            environment = dict(os.environ)
            environment.update(
                PATH=str(mock_bin) + os.pathsep + os.environ["PATH"],
                FLASH_TEST_LOG=str(log),
                FLASH_TEST_FAILURE=failure,
                TMPDIR=str(work),
            )
            result = subprocess.run(
                ["bash", str(script), "/dev/synthetic-test-port"],
                input=reply, text=True, capture_output=True, env=environment, timeout=10,
            )
            calls = log.read_text() if log.exists() else ""
            self.assertEqual(sorted(p.name for p in work.iterdir()), ["bin", "calls", "flash.sh"])
            return result, calls

    def test_validated_images_flash_at_expected_offsets(self):
        for device, chip, offsets in (
            ("m5stickc-plus2", "esp32", ("0x0",)),
            ("t-dongle-s3", "esp32s3", ("0x0", "0x8000", "0xe000", "0x10000")),
        ):
            with self.subTest(device=device):
                result, calls = self.run_flash(device)
                self.assertEqual(result.returncode, 0, result.stderr)
                flash = next(line for line in calls.splitlines() if line.startswith("esptool.py "))
                self.assertIn(f"--chip {chip} --port /dev/synthetic-test-port", flash)
                for offset in offsets:
                    self.assertIn(f" {offset} ", flash)
                self.assertIn("done!", result.stdout)

    def test_download_and_checksum_failures_never_flash(self):
        for device in ("m5stickc-plus2", "t-dongle-s3"):
            for failure in ("download", "firmware"):
                with self.subTest(device=device, failure=failure):
                    result, calls = self.run_flash(device, failure=failure)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("esptool.py", calls)
                    self.assertNotIn("unzip", calls)
                    self.assertNotIn("done!", result.stdout)

    def test_boot_checksum_and_archive_failures_never_flash(self):
        for failure in ("boot", "archive"):
            with self.subTest(failure=failure):
                result, calls = self.run_flash("t-dongle-s3", failure=failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("esptool.py", calls)

    def test_decline_and_eof_never_flash(self):
        for device in ("m5stickc-plus2", "t-dongle-s3"):
            for reply in ("n\n", ""):
                with self.subTest(device=device, reply=reply):
                    result, calls = self.run_flash(device, reply=reply)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("esptool.py", calls)

    def test_flash_failure_does_not_report_success(self):
        for device in ("m5stickc-plus2", "t-dongle-s3"):
            with self.subTest(device=device):
                result, _ = self.run_flash(device, failure="flash")
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("done!", result.stdout)


if __name__ == "__main__":
    unittest.main()
