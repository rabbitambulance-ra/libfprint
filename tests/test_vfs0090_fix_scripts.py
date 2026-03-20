import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = REPO_ROOT / "scripts"
PATCHES_DIR = REPO_ROOT / "packaging" / "patches" / "python-validity"
OVERLAY_DIR = (
    REPO_ROOT
    / "packaging"
    / "arch"
    / "python-validity-vfs0090-fix"
    / "overlay"
    / "validitysensor"
)

BOOTSTRAP = SCRIPTS_DIR / "bootstrap-python-validity-vfs0090-config.sh"
APPLY = SCRIPTS_DIR / "apply-python-validity-vfs0090-fix.sh"
REVERT = SCRIPTS_DIR / "revert-python-validity-vfs0090-fix.sh"
ENABLE_LOCAL = SCRIPTS_DIR / "enable-pam-fprintd-local.sh"

PATCH_TLS = PATCHES_DIR / "0001-tls-identity-override.patch"
PATCH_SENSOR = PATCHES_DIR / "0002-vfs0090-capture-fix.patch"


class Vfs0090FixScriptsTest(unittest.TestCase):
    def setUp(self):
        self.tmpdir = Path(tempfile.mkdtemp(prefix="vfs0090-fix-tests-"))
        self.config_dir = self.tmpdir / "config"
        self.dbus_config = self.tmpdir / "etc" / "python-validity" / "dbus-service.yaml"
        self.override_file = (
            self.tmpdir
            / "etc"
            / "systemd"
            / "system"
            / "python3-validity.service.d"
            / "override.conf"
        )
        self.pam_dir = self.tmpdir / "pam.d"
        self.sitepkg_root = self.tmpdir / "sitepkg"
        self.module_dir = self.sitepkg_root / "validitysensor"

        self.common_env = {
            "PYTHON_VALIDITY_VFS0090_FIX_ALLOW_NON_ROOT": "1",
            "PYTHON_VALIDITY_VFS0090_FIX_CONFIG_DIR": str(self.config_dir),
            "PYTHON_VALIDITY_VFS0090_FIX_DBUS_CONFIG": str(self.dbus_config),
            "PYTHON_VALIDITY_VFS0090_FIX_OVERRIDE_FILE": str(self.override_file),
            "PYTHON_VALIDITY_VFS0090_FIX_PAM_DIR": str(self.pam_dir),
            "PYTHON_VALIDITY_VFS0090_FIX_STAMP": "20990101",
            "PYTHON_VALIDITY_VFS0090_FIX_DISPLAY_MANAGER_LINK": str(self.tmpdir / "display-manager.service"),
            "PYTHON_VALIDITY_VFS0090_FIX_SYSTEMCTL": "/bin/true",
            "PYTHON_VALIDITY_VFS0090_FIX_DATA_DIR": str(REPO_ROOT),
            "PYTHON_VALIDITY_VFS0090_FIX_MODULE_DIR": str(self.module_dir),
            "PYTHON_VALIDITY_VFS0090_FIX_SITEPKG_ROOT": str(self.sitepkg_root),
        }

    def tearDown(self):
        shutil.rmtree(self.tmpdir)

    def run_script(self, script: Path, *args: str, env: dict | None = None) -> subprocess.CompletedProcess:
        merged_env = os.environ.copy()
        merged_env.update(self.common_env)
        if env:
            merged_env.update(env)
        return subprocess.run(
            [str(script), *args],
            check=True,
            capture_output=True,
            text=True,
            env=merged_env,
            cwd=REPO_ROOT,
        )

    def write_fake_pam(self, name: str, body: str) -> Path:
        self.pam_dir.mkdir(parents=True, exist_ok=True)
        path = self.pam_dir / name
        path.write_text(body)
        return path

    def prepare_fake_sitepkg(self) -> tuple[str, str]:
        self.module_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy(OVERLAY_DIR / "tls.py", self.module_dir / "tls.py")
        shutil.copy(OVERLAY_DIR / "sensor.py", self.module_dir / "sensor.py")

        subprocess.run(
            ["patch", "-R", "--silent", "-p1", "-d", str(self.sitepkg_root), "-i", str(PATCH_TLS)],
            check=True,
            capture_output=True,
            text=True,
        )
        subprocess.run(
            ["patch", "-R", "--silent", "-p1", "-d", str(self.sitepkg_root), "-i", str(PATCH_SENSOR)],
            check=True,
            capture_output=True,
            text=True,
        )

        tls_before = (self.module_dir / "tls.py").read_text()
        sensor_before = (self.module_dir / "sensor.py").read_text()
        return tls_before, sensor_before

    def test_bootstrap_writes_identity_and_dbus_mapping(self):
        result = self.run_script(
            BOOTSTRAP,
            "--product-name",
            "ExampleProduct",
            "--product-serial",
            "ExampleSerial",
            "--dbus-user",
            "example-user",
            "--dbus-sid",
            "S-1-5-21-1-2-3-1000",
        )

        self.assertIn("Bootstrap complete.", result.stdout)
        self.assertEqual(
            (self.config_dir / "identity.env").read_text(),
            'PYTHON_VALIDITY_PRODUCT_NAME="ExampleProduct"\n'
            'PYTHON_VALIDITY_PRODUCT_SERIAL="ExampleSerial"\n',
        )
        self.assertEqual(
            self.dbus_config.read_text(),
            "user_to_sid:\n"
            "  example-user: S-1-5-21-1-2-3-1000\n",
        )

    def test_bootstrap_reads_current_override_when_arguments_are_omitted(self):
        self.override_file.parent.mkdir(parents=True, exist_ok=True)
        self.override_file.write_text(
            "[Service]\n"
            "Environment=PYTHON_VALIDITY_PRODUCT_NAME=CurrentProduct\n"
            "Environment=PYTHON_VALIDITY_PRODUCT_SERIAL=CurrentSerial\n"
        )

        self.run_script(BOOTSTRAP)

        self.assertEqual(
            (self.config_dir / "identity.env").read_text(),
            'PYTHON_VALIDITY_PRODUCT_NAME="CurrentProduct"\n'
            'PYTHON_VALIDITY_PRODUCT_SERIAL="CurrentSerial"\n',
        )

    def test_enable_local_pam_is_idempotent_and_warn_free(self):
        sudo_pam = self.write_fake_pam(
            "sudo",
            "#%PAM-1.0\n"
            "auth\tinclude\tsystem-auth\n"
            "account\tinclude\tsystem-auth\n",
        )
        su_pam = self.write_fake_pam(
            "su",
            "#%PAM-1.0\n"
            "auth            sufficient      pam_rootok.so\n"
            "auth            required        pam_unix.so\n",
        )
        self.write_fake_pam(
            "su-l",
            "#%PAM-1.0\n"
            "auth            sufficient      pam_rootok.so\n"
            "auth            required        pam_unix.so\n",
        )
        self.write_fake_pam(
            "vlock",
            "#%PAM-1.0\n"
            "auth            required        pam_unix.so\n",
        )

        first = self.run_script(ENABLE_LOCAL)
        second = self.run_script(ENABLE_LOCAL)

        self.assertNotIn("escape sequence", first.stderr)
        self.assertNotIn("escape sequence", second.stderr)

        expected = "auth       sufficient   pam_fprintd.so max-tries=3 timeout=10"
        self.assertEqual(sudo_pam.read_text().count(expected), 1)
        self.assertEqual(su_pam.read_text().count(expected), 0)

    def test_enable_local_can_optionally_patch_su(self):
        self.write_fake_pam(
            "su",
            "#%PAM-1.0\n"
            "auth            sufficient      pam_rootok.so\n"
            "auth            required        pam_unix.so\n",
        )
        self.write_fake_pam(
            "su-l",
            "#%PAM-1.0\n"
            "auth            sufficient      pam_rootok.so\n"
            "auth            required        pam_unix.so\n",
        )
        self.write_fake_pam(
            "vlock",
            "#%PAM-1.0\n"
            "auth            required        pam_unix.so\n",
        )

        self.run_script(ENABLE_LOCAL, "--include-su")

        expected = "auth       sufficient   pam_fprintd.so max-tries=3 timeout=10"
        self.assertEqual((self.pam_dir / "su").read_text().count(expected), 1)
        self.assertEqual((self.pam_dir / "su-l").read_text().count(expected), 1)

    def test_apply_and_revert_round_trip(self):
        tls_before, sensor_before = self.prepare_fake_sitepkg()
        self.config_dir.mkdir(parents=True, exist_ok=True)
        (self.config_dir / "identity.env").write_text(
            'PYTHON_VALIDITY_PRODUCT_NAME="ExampleProduct"\n'
            'PYTHON_VALIDITY_PRODUCT_SERIAL="ExampleSerial"\n'
        )
        self.dbus_config.parent.mkdir(parents=True, exist_ok=True)
        self.dbus_config.write_text(
            "user_to_sid:\n"
            "  example-user: S-1-5-21-1-2-3-1000\n"
        )

        apply_result = self.run_script(APPLY)
        tls_after = (self.module_dir / "tls.py").read_text()
        sensor_after = (self.module_dir / "sensor.py").read_text()

        self.assertIn("python-validity VFS0090 fix is applied.", apply_result.stdout)
        self.assertIn("PYTHON_VALIDITY_PRODUCT_NAME", tls_after)
        self.assertIn("Unable to read DMI pairing identity", tls_after)
        self.assertNotIn("product_name = 'VirtualBox'", tls_after)
        self.assertIn("effective_mode = CaptureMode.ENROLL if mode == CaptureMode.IDENTIFY else mode", sensor_after)
        self.assertIn("unpack('<HHHHL', res[:12])", sensor_after)
        self.assertEqual(
            self.override_file.read_text(),
            "[Service]\n"
            f"EnvironmentFile=-{self.config_dir / 'identity.env'}\n",
        )

        self.run_script(REVERT)

        self.assertEqual((self.module_dir / "tls.py").read_text(), tls_before)
        self.assertEqual((self.module_dir / "sensor.py").read_text(), sensor_before)


if __name__ == "__main__":
    unittest.main()
