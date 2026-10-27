import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / '.github/scripts/setup-android-sdk.ps1'


@unittest.skipUnless(shutil.which('pwsh'), 'PowerShell is not installed')
class RunnerSdkSetup(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.sdk = self.root / 'runner SDK with spaces'
        self.tools = self.sdk / 'cmdline-tools/latest/bin'
        self.tools.mkdir(parents=True)
        self.env_file = self.root / 'github-env'
        self.path_file = self.root / 'github-path'
        self.env_file.write_text('EXISTING=preserved\n')
        self.path_file.touch()
        self.env = dict(os.environ)
        self.env.pop('ANDROID_HOME', None)
        self.env.pop('ANDROID_SDK_ROOT', None)
        self.env.update(GITHUB_ENV=str(self.env_file), GITHUB_PATH=str(self.path_file))

    def run_setup(self):
        return subprocess.run(['pwsh', '-NoProfile', '-File', str(SCRIPT)],
                              env=self.env, capture_output=True, text=True)

    def assert_published(self):
        values = self.env_file.read_text(encoding='utf-8-sig').splitlines()
        self.assertIn('EXISTING=preserved', values)
        self.assertIn('ANDROID_SDK_ROOT=' + str(self.sdk), values)
        self.assertIn('ANDROID_HOME=' + str(self.sdk), values)
        paths = [Path(value) for value in self.path_file.read_text(encoding='utf-8-sig').splitlines()]
        self.assertIn(self.tools, paths)
        self.assertIn(self.sdk / 'platform-tools', paths)

    def test_sdkmanager_outside_path_is_exported(self):
        (self.tools / 'sdkmanager').touch()
        self.env['ANDROID_SDK_ROOT'] = str(self.sdk)
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_published()

    def test_android_home_and_windows_batch_manager_are_supported(self):
        (self.tools / 'sdkmanager.bat').touch()
        self.env['ANDROID_HOME'] = str(self.sdk)
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_published()

    def test_missing_command_line_tools_fail_before_publishing(self):
        self.env['ANDROID_SDK_ROOT'] = str(self.sdk)
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('command-line tools are missing', result.stderr)
        self.assertEqual(self.env_file.read_text(), 'EXISTING=preserved\n')
        self.assertEqual(self.path_file.read_text(), '')

    def test_missing_sdk_root_fails_before_publishing(self):
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('did not provide', result.stderr)
        self.assertEqual(self.path_file.read_text(), '')


if __name__ == '__main__':
    unittest.main()
