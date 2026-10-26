#!/usr/bin/env python3
"""Check runtime library manifests inside a mod ZIP, standalone .love, or APK."""
import argparse
import io
import json
from pathlib import PurePosixPath
import zipfile


def jsonc(data):
    text = data.decode('utf-8-sig')
    output = []
    index = 0
    quoted = escaped = False
    while index < len(text):
        char = text[index]
        if quoted:
            output.append(char)
            if escaped:
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == '"':
                quoted = False
        elif char == '"':
            quoted = True
            output.append(char)
        elif text[index:index + 2] == '//':
            end = text.find('\n', index)
            index = len(text) if end == -1 else end
            output.append('\n')
            continue
        elif text[index:index + 2] == '/*':
            end = text.find('*/', index + 2)
            if end == -1:
                raise ValueError('Unterminated JSONC comment')
            index = end + 2
            output.append(' ')
            continue
        else:
            output.append(char)
        index += 1
    text = ''.join(output)
    output = []
    quoted = escaped = False
    for index, char in enumerate(text):
        if quoted:
            if escaped:
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == '"':
                quoted = False
        elif char == '"':
            quoted = True
        elif char == ',' and text[index + 1:].lstrip().startswith(('}', ']')):
            char = ' '
        output.append(char)
    return json.loads(''.join(output))


def verify(archive, mod_id):
    with zipfile.ZipFile(archive) as package:
        if 'assets/game.love' in package.namelist():
            return verify(io.BytesIO(package.read('assets/game.love')), mod_id)
        names = set(package.namelist())
        prefix = f'mods/{mod_id}/' if f'mods/{mod_id}/mod.json' in names else ''
        manifest = jsonc(package.read(prefix + 'mod.json'))
        if manifest.get('id') != mod_id:
            raise ValueError(f'Expected mod {mod_id}, got {manifest.get("id")}')
        libraries = {}
        for name in names:
            relative = name.removeprefix(prefix)
            if not name.startswith(prefix) or len(PurePosixPath(relative).parts) != 3:
                continue
            if not relative.startswith('libraries/') or not relative.endswith('/lib.json'):
                continue
            library = jsonc(package.read(name))
            library_id = library['id']
            if library_id in libraries:
                raise ValueError(f'Duplicate library ID: {library_id}')
            libraries[library_id] = library
        for library_id, enabled in manifest.get('optionalLibraries', {}).items():
            if enabled and library_id not in libraries:
                raise ValueError(f'Enabled optional library is missing: {library_id}')
        for library_id, library in libraries.items():
            for dependency in library.get('dependencies', []):
                if dependency not in libraries:
                    raise ValueError(f'{library_id} requires missing library: {dependency}')
        print(f'Packaged libraries verified: {mod_id} ({len(libraries)} libraries)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive')
    parser.add_argument('--mod-id', required=True)
    args = parser.parse_args()
    verify(args.archive, args.mod_id)
