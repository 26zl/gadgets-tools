import base64
import json
import os
from pathlib import Path
import shlex
import shutil
import struct
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
STUB = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps([name, *args]) + "\n")
if name == "adb":
    if args == ["get-state"]:
        print("device")
    elif args[:3] == ["shell", "pm", "list"]:
        print(os.environ.get("PACKAGES", ""))
    elif args[:2] == ["shell", "getprop"]:
        print({"ro.product.device": os.environ.get("DEVICE", "beyond1lte"),
               "ro.product.model": "Synthetic phone"}.get(args[2], "test"))
    elif args == ["shell", "uname", "-r"]:
        print("test-nethunter")
    elif args and args[0] == "shell" and "ls -d /storage/" in args[1]:
        print(os.environ.get("SD_MOUNT", "/storage/1234-ABCD"))
    elif args and args[0] == "shell" and args[1].startswith("su -c"):
        sys.exit(int(os.environ.get("REMOTE_STATUS", "0")))
    elif args and args[0] == "push":
        sys.exit(int(os.environ.get("PUSH_STATUS", "0"))) if os.environ.get("PUSH_STATUS") else None
        shutil.copyfile(args[1], Path(os.environ["CAPTURE_DIR"]) / Path(args[2]).name)
    elif args and args[0] == "install":
        sys.exit(int(os.environ.get("INSTALL_STATUS", "0")))
elif name in ("curl", "gh"):
    status = int(os.environ.get("DOWNLOAD_STATUS", "0"))
    if status:
        sys.exit(status)
    if name == "gh":
        (Path(args[args.index("--dir") + 1]) / "synthetic-arm64.apk").write_bytes(b"synthetic APK")
    elif "-o" in args:
        Path(args[args.index("-o") + 1]).write_bytes(b"synthetic APK")
    else:
        print(json.dumps({"packages": [{"versionCode": 1}]}))
elif name == "git":
    if "archive" in args:
        Path(args[args.index("-o") + 1]).touch()
    sys.exit(int(os.environ.get("GIT_STATUS", "0")))
elif name == "heimdall":
    print("test heimdall")
    sys.exit(12 if "flash" in args else 0)
elif name == "prepare-upgrade.sh":
    sys.exit(int(os.environ.get("DOWNLOAD_STATUS", "0")))
elif name == "verify.sh":
    sys.exit(0)
else:
    sys.exit(99)
'''


class PhoneScriptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.capture = self.root / "capture"
        self.capture.mkdir()
        self.log = self.root / "calls.jsonl"
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        CALL_LOG=str(self.log),
                        CAPTURE_DIR=str(self.capture))
        for name in ("adb", "git", "heimdall", "gh", "curl"):
            self.stub(name, self.bin)

    def stub(self, name, directory):
        path = directory / name
        path.write_text(STUB)
        path.chmod(0o755)
        return path

    def run_script(self, name, *args, directory=SCRIPTS):
        return subprocess.run(["bash", str(directory / name), *args],
                              env=self.env, text=True, input="\n" * 20,
                              capture_output=True, timeout=15)

    def calls(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_ssh_rejects_invalid_port_before_device_access(self):
        for port in ("0", "65536", "22'; exit 0; #", "-1", "a"):
            with self.subTest(port=port):
                self.assertNotEqual(self.run_script("ssh-setup.sh", "unused.pub", port).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_ssh_key_comment_is_only_transferred_as_data(self):
        key = self.root / "test.pub"
        comment = "synthetic'; touch /synthetic-marker; #"
        algorithm = b"ssh-ed25519"
        wire = struct.pack(">I", len(algorithm)) + algorithm + struct.pack(">I", 32) + bytes(range(32))
        key.write_text(f"ssh-ed25519 {base64.b64encode(wire).decode()} {comment}\n")
        result = self.run_script("ssh-setup.sh", str(key), "08022")
        self.assertEqual(result.returncode, 0, result.stderr)
        inner = (self.capture / "ssh-inner.sh").read_text()
        self.assertNotIn(comment, inner)
        self.assertEqual((self.capture / "ssh-public-key.pub").read_text(), key.read_text())
        self.assertIn("KbdInteractiveAuthentication no", inner)
        self.assertIn("/usr/sbin/sshd -t", inner)
        service = (self.capture / "chroot-sshd.sh").read_text()
        self.assertIn("set -eu", service)
        self.assertIn("pkill -x sshd 2>/dev/null || true", service)
        syntax = subprocess.run(["bash", "-n", str(self.capture / "ssh-inner.sh")], capture_output=True)
        self.assertEqual(syntax.returncode, 0, syntax.stderr)

    def test_ssh_rejects_invalid_key_without_uploading(self):
        key = self.root / "invalid.pub"
        key.write_text("ssh-ed25519 invalid-synthetic-key\n")
        self.assertNotEqual(self.run_script("ssh-setup.sh", str(key)).returncode, 0)
        self.assertFalse(any(call[:2] == ["adb", "push"] for call in self.calls()))

    def test_ssh_rejects_private_key_file_without_uploading(self):
        key = self.root / "wrong-input"
        key.write_text("-----BEGIN SYNTHETIC PRIVATE INPUT-----\n")
        self.assertNotEqual(self.run_script("ssh-setup.sh", str(key)).returncode, 0)
        self.assertFalse(any(call[:2] == ["adb", "push"] for call in self.calls()))

    def test_ssh_stops_after_failed_mount_preparation(self):
        key = self.root / "test.pub"
        algorithm = b"ssh-ed25519"
        wire = struct.pack(">I", len(algorithm)) + algorithm + struct.pack(">I", 32) + bytes(range(32))
        key.write_text(f"ssh-ed25519 {base64.b64encode(wire).decode()} synthetic\n")
        self.env["REMOTE_STATUS"] = "12"
        self.assertEqual(self.run_script("ssh-setup.sh", str(key)).returncode, 12)
        call = next(call for call in self.calls() if call[:2] == ["adb", "shell"])
        outer = shlex.split(call[2])
        self.assertTrue(outer[2].startswith("set -e; "))
        self.assertFalse(any(call[:2] == ["adb", "push"] for call in self.calls()))

    def test_sdcard_paths_remain_single_arguments_at_both_shell_layers(self):
        phone_path = "/sdcard/synthetic'; touch /synthetic-marker; # file.txt"
        result = self.run_script("sdcard.sh", "move", phone_path)
        self.assertEqual(result.returncode, 0, result.stderr)
        call = next(call for call in self.calls() if call[:2] == ["adb", "shell"] and call[2].startswith("su -c"))
        outer = shlex.split(call[2])
        self.assertEqual(outer[:2], ["su", "-c"])
        self.assertEqual(len(outer), 3)
        self.assertEqual(shlex.split(outer[2]), ["mv", "--", phone_path,
                         "/storage/1234-ABCD/", "&&", "echo", "  ok"])

    def test_sdcard_propagates_move_failure(self):
        self.env["REMOTE_STATUS"] = "12"
        self.assertEqual(self.run_script("sdcard.sh", "move", "/sdcard/test.txt").returncode, 12)

    def test_sdcard_rejects_invalid_mount(self):
        self.env["SD_MOUNT"] = "/storage/1234-ABCD'; exit 0; #"
        self.assertNotEqual(self.run_script("sdcard.sh", "info").returncode, 0)
        self.assertEqual(len(self.calls()), 2)

    def test_sdcard_requires_files(self):
        self.assertNotEqual(self.run_script("sdcard.sh", "move").returncode, 0)

    def test_verify_rejects_wrong_device(self):
        self.env["DEVICE"] = "synthetic-other-device"
        self.assertNotEqual(self.run_script("verify.sh").returncode, 0)

    def test_verify_requires_exact_packages(self):
        self.env["PACKAGES"] = "\n".join(f"package:{pkg}" for pkg in (
            "com.topjohnwu.magisk", "com.offsec.nethunter.store",
            "com.offsec.nhterm", "com.offsec.nethunter.kex"))
        result = self.run_script("verify.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("com.offsec.nethunter MISSING", result.stdout)

    def test_verify_succeeds_when_all_checks_pass(self):
        self.env["PACKAGES"] = "\n".join(f"package:{pkg}\r" for pkg in (
            "com.topjohnwu.magisk", "com.offsec.nethunter", "com.offsec.nethunter.store",
            "com.offsec.nhterm", "com.offsec.nethunter.kex"))
        self.assertEqual(self.run_script("verify.sh").returncode, 0)

    def stage_upgrade(self):
        scripts = self.root / "scripts"
        scripts.mkdir()
        source = (SCRIPTS / "upgrade.sh").read_text()
        source = source.replace('DIR="$HOME/nethunter-s10"',
                                f"DIR={shlex.quote(str(self.root / 'nethunter-s10'))}")
        (scripts / "upgrade.sh").write_text(source)
        self.stub("verify.sh", scripts)
        self.stub("prepare-upgrade.sh", scripts)
        files = self.root / "nethunter-s10"
        files.mkdir()
        for filename in ("lineage-test-beyond1lte-signed.zip", "Magisk-v-test.apk",
                         "kali-nethunter-testfull.zip", "recovery.img", "vbmeta.img"):
            (files / filename).touch()
        return scripts

    def test_upgrade_stops_after_failed_download(self):
        scripts = self.stage_upgrade()
        self.env["DOWNLOAD_STATUS"] = "13"
        self.assertEqual(self.run_script("upgrade.sh", directory=scripts).returncode, 13)
        self.assertFalse(any(call[0] == "heimdall" and "flash" in call for call in self.calls()))

    def test_upgrade_stops_after_failed_flash(self):
        scripts = self.stage_upgrade()
        self.assertEqual(self.run_script("upgrade.sh", directory=scripts).returncode, 12)
        self.assertFalse(any(call[:3] == ["adb", "-d", "sideload"] for call in self.calls()))

    def test_setup_limits_submodules_and_stops_on_failure(self):
        self.env["GIT_STATUS"] = "15"
        self.assertEqual(self.run_script("setup.sh").returncode, 15)
        git_call = next(call for call in self.calls() if call[0] == "git")
        self.assertEqual(git_call[-3:], ["--", "netsec-auditor", "cybersec-toolkit"])
        self.assertFalse(any(call[:2] == ["adb", "shell"] for call in self.calls()))

    def test_setup_quotes_root_command_and_stops_after_mount_failure(self):
        self.env["REMOTE_STATUS"] = "12"
        self.assertEqual(self.run_script("setup.sh").returncode, 12)
        call = next(call for call in self.calls() if call[:2] == ["adb", "shell"])
        outer = shlex.split(call[2])
        self.assertEqual(len(outer), 3)
        self.assertEqual(outer[:2], ["su", "-c"])
        self.assertTrue(outer[2].startswith("set -e; "))
        self.assertIn("for m in dev proc sys; do chroot $K /usr/bin/mount --make-rslave /$m; done", outer[2])
        self.assertFalse(any(call[:2] == ["adb", "push"] for call in self.calls()))

    def test_app_installers_report_download_failure_and_continue(self):
        self.env["DOWNLOAD_STATUS"] = "12"
        for script in ("apps.sh", "extras.sh"):
            with self.subTest(script=script):
                self.log.unlink(missing_ok=True)
                result = self.run_script(script)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertGreater(result.stdout.count("FAILED"), 1)
                self.assertGreater(sum(call[0] in ("curl", "gh") for call in self.calls()), 1)

    def test_app_installers_report_device_install_failure_and_continue(self):
        self.env["INSTALL_STATUS"] = "12"
        for script in ("apps.sh", "extras.sh"):
            with self.subTest(script=script):
                self.log.unlink(missing_ok=True)
                result = self.run_script(script)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertGreater(sum(call[:2] == ["adb", "install"] for call in self.calls()), 1)

    def test_app_installers_succeed_with_mocked_downloads_and_installs(self):
        for script in ("apps.sh", "extras.sh"):
            with self.subTest(script=script):
                result = self.run_script(script)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("FAILED", result.stdout)

    def test_app_installers_skip_exact_installed_packages_without_downloads(self):
        for script in ("apps.sh", "extras.sh"):
            with self.subTest(script=script):
                source = (SCRIPTS / script).read_text()
                if script == "apps.sh":
                    import re
                    packages = re.findall(r'"([\w.]+)\|', source)
                    packages += ["org.fdroid.fdroid", "com.aurora.store"]
                else:
                    packages = [line.split()[1] for line in source.splitlines()
                                if line.startswith(("fdroid ", "ghub "))]
                self.env["PACKAGES"] = "\n".join(f"package:{pkg}" for pkg in packages)
                self.log.unlink(missing_ok=True)
                result = self.run_script(script)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(any(call[0] in ("gh", "curl") for call in self.calls()))
                self.assertFalse(any(call[:2] == ["adb", "install"] for call in self.calls()))


if __name__ == "__main__":
    unittest.main()
