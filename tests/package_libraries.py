"""Regress runtime library validation in real nested archive layouts."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import unittest
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    'verify_package_libraries', ROOT / '.github/scripts/verify-package-libraries.py'
)
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)
MOD_ID = 'fixture-mod'


def archive(entries):
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w') as package:
        for name, value in entries.items():
            package.writestr(name, value)
    return output.getvalue()


def contents(selection, libraries=(), prefix=''):
    entries = {
        prefix + 'mod.json': json.dumps({
            'id': MOD_ID, 'optionalLibraries': selection,
        }),
    }
    for directory, manifest in libraries:
        base = prefix + 'libraries/' + directory + '/'
        entries[base + 'lib.json'] = json.dumps(manifest)
        entries[base + 'lib.lua'] = 'return {}'
    return entries


class PackageLibrariesTests(unittest.TestCase):
    def verify(self, entries, nested=False):
        data = archive(entries)
        if nested:
            data = archive({'assets/game.love': data, 'AndroidManifest.xml': b'AXML'})
        with contextlib.redirect_stdout(io.StringIO()):
            CHECKER.verify(io.BytesIO(data), MOD_ID)

    def test_enabled_packs_keep_their_required_dependency(self):
        libraries = (
            ('vendor-manager', {'id': 'magical-glass'}),
            ('vendor-monsters', {
                'id': 'undertale_monsters_recreation', 'dependencies': ['magical-glass'],
            }),
        )
        for prefix in ('', 'mods/' + MOD_ID + '/'):
            with self.subTest(prefix=prefix):
                self.verify(contents({
                    'magical-glass': True, 'undertale_monsters_recreation': True,
                }, libraries, prefix))

    def test_normalized_apk_without_disabled_packs(self):
        self.verify(contents({
            'magical-glass': False, 'undertale_monsters_recreation': False,
        }, prefix='mods/' + MOD_ID + '/'), nested=True)

    def test_original_missing_library_apk_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Enabled optional library is missing'):
            self.verify(contents({
                'magical-glass': False, 'undertale_monsters_recreation': True,
            }, prefix='mods/' + MOD_ID + '/'), nested=True)

    def test_retained_missing_dependency_is_rejected(self):
        entries = contents({}, [('vendor-monsters', {
            'id': 'undertale_monsters_recreation', 'dependencies': ['magical-glass'],
        })])
        with self.assertRaisesRegex(ValueError, 'requires missing library'):
            self.verify(entries)

    def test_content_libraries_do_not_require_an_entry_point(self):
        for value in (None, ''):
            with self.subTest(value=value):
                entries = contents({}, [('manager', {'id': 'magical-glass'})])
                path = 'libraries/manager/lib.lua'
                if value is None:
                    del entries[path]
                else:
                    entries[path] = value
                self.verify(entries)

    def test_duplicate_library_ids_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate library ID'):
            self.verify(contents({}, [
                ('one', {'id': 'magical-glass'}), ('two', {'id': 'magical-glass'}),
            ]))

    def test_debug_and_optional_dependencies_may_remain(self):
        self.verify(contents({'magical-glass': False}, [
            ('manager', {'id': 'magical-glass'}),
            ('terminal', {'id': 'terminal-cli', 'optionalDependencies': ['absent']}),
        ]))

    def test_jsonc_preserves_comment_markers_inside_strings(self):
        manifest = CHECKER.jsonc(b'''{
            // A real comment.
            "url": "https://example.invalid//path/*literal*/",
            "quote": "escaped \\" quote",
            "array": [1, /* another comment */ 2,],
        }''')
        self.assertEqual(manifest['url'], 'https://example.invalid//path/*literal*/')
        self.assertEqual(manifest['quote'], 'escaped " quote')
        self.assertEqual(manifest['array'], [1, 2])


if __name__ == '__main__':
    unittest.main()
