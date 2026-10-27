#!/usr/bin/env python3
"""Prepare stable Android release signing and verify the resulting APK."""
import argparse
import base64
import hashlib
import os
from pathlib import Path
import re
import ssl
import subprocess


MAX_VERSION_CODE = 2_100_000_000


def version_metadata(tag):
    match = re.fullmatch(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', tag)
    if not match:
        raise ValueError('Android release tag must be vMAJOR.MINOR.PATCH')
    major, minor, patch = map(int, match.groups())
    if minor > 999 or patch > 999:
        raise ValueError('Android minor and patch versions must be at most 999')
    code = major * 1_000_000 + minor * 1_000 + patch
    if not 0 < code <= MAX_VERSION_CODE:
        raise ValueError('Android version code must be within 1..2100000000')
    return code, '.'.join(match.groups())


def certificate_digest(value):
    digest = value.replace(':', '').strip().lower()
    if not re.fullmatch(r'[0-9a-f]{64}', digest):
        raise ValueError('ANDROID_SIGNING_CERT_SHA256 must contain a SHA-256 certificate fingerprint')
    return digest


def prepare(tag, prefix, keystore, environment_file):
    code, name = version_metadata(tag)
    if not re.fullmatch(r'[A-Z][A-Z0-9_]*', prefix):
        raise ValueError('Invalid project environment prefix')
    required = ('KEYSTORE_BASE64', 'STORE_PASSWORD', 'KEY_ALIAS', 'KEY_PASSWORD', 'CERT_SHA256')
    values = {}
    for suffix in required:
        key = 'ANDROID_SIGNING_' + suffix
        value = os.environ.get(key, '')
        if not value:
            raise ValueError(f'Missing required Android release configuration: {key}')
        if suffix != 'KEYSTORE_BASE64' and ('\n' in value or '\r' in value):
            raise ValueError(f'Android release configuration contains a newline: {key}')
        values[suffix] = value
    expected = certificate_digest(values['CERT_SHA256'])
    key_bytes = base64.b64decode(''.join(values['KEYSTORE_BASE64'].split()), validate=True)
    if not key_bytes:
        raise ValueError('Android release keystore is empty')
    keystore = Path(keystore).resolve()
    descriptor = os.open(keystore, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, 'wb') as output:
            output.write(key_bytes)
        pem = subprocess.check_output([
            'keytool', '-exportcert', '-rfc', '-keystore', str(keystore),
            '-storepass:env', 'ANDROID_SIGNING_STORE_PASSWORD', '-alias', values['KEY_ALIAS'],
        ], text=True, stderr=subprocess.PIPE)
        certificate = ssl.PEM_cert_to_DER_cert(pem)
        if hashlib.sha256(certificate).hexdigest() != expected:
            raise ValueError('Release keystore certificate does not match ANDROID_SIGNING_CERT_SHA256')
        settings = {
            f'{prefix}_ANDROID_SIGNING_KEYSTORE': str(keystore),
            f'{prefix}_ANDROID_SIGNING_STORE_PASSWORD': values['STORE_PASSWORD'],
            f'{prefix}_ANDROID_SIGNING_KEY_ALIAS': values['KEY_ALIAS'],
            f'{prefix}_ANDROID_SIGNING_KEY_PASSWORD': values['KEY_PASSWORD'],
            f'{prefix}_ANDROID_VERSION_CODE': str(code),
            f'{prefix}_ANDROID_VERSION_NAME': name,
        }
        with Path(environment_file).open('a', encoding='utf-8') as output:
            for key, value in settings.items():
                if '\n' in value or '\r' in value:
                    raise ValueError('Invalid newline in Android release setting')
                output.write(f'{key}={value}\n')
    except BaseException:
        keystore.unlink(missing_ok=True)
        raise
    print(f'Android release signing prepared: {tag}, versionCode={code}')


def verify(apk, tag, expected_certificate, application_id, sdk):
    expected_code, expected_name = version_metadata(tag)
    expected_certificate = certificate_digest(expected_certificate)
    tools = Path(sdk) / 'build-tools' / '34.0.0'
    signature = subprocess.check_output([
        'java', '-jar', str(tools / 'lib' / 'apksigner.jar'),
        'verify', '--print-certs', str(apk),
    ], text=True, stderr=subprocess.PIPE)
    actual = re.findall(r'Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)', signature)
    if len(actual) != 1 or certificate_digest(actual[0]) != expected_certificate:
        raise ValueError('APK signer certificate does not match the configured release certificate')
    aapt = tools / ('aapt.exe' if os.name == 'nt' else 'aapt')
    metadata = subprocess.check_output([str(aapt), 'dump', 'badging', str(apk)], text=True, stderr=subprocess.PIPE)
    package = re.search(r"^package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'", metadata, re.M)
    if not package or package.groups() != (application_id, str(expected_code), expected_name):
        raise ValueError('APK package ID, version code, or version name does not match the release tag')
    print(f'Android release APK verified: {application_id}, versionCode={expected_code}, certificate={expected_certificate}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    version = commands.add_parser('version-code')
    version.add_argument('tag')
    setup = commands.add_parser('prepare')
    setup.add_argument('--tag', required=True)
    setup.add_argument('--env-prefix', required=True)
    setup.add_argument('--keystore', required=True)
    setup.add_argument('--output-env', required=True)
    check = commands.add_parser('verify')
    check.add_argument('--apk', required=True)
    check.add_argument('--tag', required=True)
    check.add_argument('--certificate', required=True)
    check.add_argument('--application-id', required=True)
    check.add_argument('--sdk', default=os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME'))
    args = parser.parse_args()
    try:
        if args.command == 'version-code':
            print(version_metadata(args.tag)[0])
        elif args.command == 'prepare':
            prepare(args.tag, args.env_prefix, args.keystore, args.output_env)
        else:
            if not args.sdk:
                raise ValueError('ANDROID_SDK_ROOT or --sdk is required')
            verify(args.apk, args.tag, args.certificate, args.application_id, args.sdk)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        # Never echo signing command output or environment values.
        parser.exit(1, f'Android release verification failed: {error}\n')


if __name__ == '__main__':
    main()
