#!/usr/bin/env python3
import base64
import hashlib
import ssl
import importlib.util
import os
from pathlib import Path
import tempfile
import sys
sys.dont_write_bytecode = True
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('android_release', Path(__file__).resolve().parents[1] / '.github/scripts/android-release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class AndroidReleaseTests(unittest.TestCase):
    def test_monotonic_release_versions(self):
        self.assertEqual(release.version_metadata('v0.3.1'), (3001, '0.3.1'))
        tags = ['v0.0.1', 'v0.999.999', 'v1.0.0', 'v1.0.1', 'v2100.0.0']
        codes = [release.version_metadata(tag)[0] for tag in tags]
        self.assertEqual(codes, sorted(set(codes)))

    def test_invalid_or_ambiguous_versions(self):
        for tag in ('v0.0.0', 'v0.3.1000', 'v0.1000.0', 'v2100.0.1', 'v01.2.3', 'v1.2.3-rc.1', '1.2.3'):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.version_metadata(tag)

    def test_formal_release_requires_signing_configuration(self):
        with tempfile.TemporaryDirectory() as temporary:
            key = Path(temporary) / 'release.jks'
            with patch.dict(os.environ, {}, clear=True), self.assertRaisesRegex(ValueError, 'Missing required'):
                release.prepare('v0.3.1', 'PROJECT', key, Path(temporary) / 'env')
            self.assertFalse(key.exists())

    def test_verified_keystore_maps_to_project_settings(self):
        certificate = b'public certificate fixture'
        environment = {
            'ANDROID_SIGNING_KEYSTORE_BASE64': base64.b64encode(b'keystore fixture').decode(),
            'ANDROID_SIGNING_STORE_PASSWORD': 'test-store-password',
            'ANDROID_SIGNING_KEY_ALIAS': 'release',
            'ANDROID_SIGNING_KEY_PASSWORD': 'test-key-password',
            'ANDROID_SIGNING_CERT_SHA256': hashlib.sha256(certificate).hexdigest(),
        }
        with tempfile.TemporaryDirectory() as temporary:
            key = Path(temporary) / 'release.jks'
            settings = Path(temporary) / 'environment'
            with patch.dict(os.environ, environment, clear=True), patch.object(
                release.subprocess, 'check_output', return_value=ssl.DER_cert_to_PEM_cert(certificate)
            ):
                release.prepare('v0.3.1', 'PROJECT', key, settings)
            self.assertEqual(key.stat().st_mode & 0o777, 0o600)
            text = settings.read_text()
            self.assertIn('PROJECT_ANDROID_VERSION_CODE=3001\n', text)
            self.assertIn('PROJECT_ANDROID_VERSION_NAME=0.3.1\n', text)
            self.assertIn('PROJECT_ANDROID_SIGNING_KEY_ALIAS=release\n', text)

    def test_apk_identity_and_certificate_must_match(self):
        digest = 'a' * 64
        signature = f'Signer #1 certificate SHA-256 digest: {digest}\n'
        package = "package: name='org.example.game' versionCode='3001' versionName='0.3.1' platformBuildVersionName='14'\n"
        with patch.object(release.subprocess, 'check_output', side_effect=[signature, package]):
            release.verify('test.apk', 'v0.3.1', digest, 'org.example.game', '/sdk')
        with patch.object(release.subprocess, 'check_output', return_value=signature), self.assertRaisesRegex(ValueError, 'certificate'):
            release.verify('test.apk', 'v0.3.1', 'b' * 64, 'org.example.game', '/sdk')
        with patch.object(release.subprocess, 'check_output', side_effect=[signature, package]), self.assertRaisesRegex(ValueError, 'version code'):
            release.verify('test.apk', 'v0.3.2', digest, 'org.example.game', '/sdk')


if __name__ == '__main__':
    unittest.main()
