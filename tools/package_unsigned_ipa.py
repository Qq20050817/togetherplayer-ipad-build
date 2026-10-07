#!/usr/bin/env python3
"""Package a successful unsigned iOS device build; signing happens separately."""
import argparse
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=pathlib.Path)
    parser.add_argument('output', type=pathlib.Path)
    parser.add_argument('--notices', type=pathlib.Path, required=True)
    args = parser.parse_args()
    app = args.app.resolve()
    output = args.output.resolve()
    if not app.is_dir() or app.suffix != '.app':
        parser.error('A successfully built .app directory is required')
    with (app / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        parser.error('Only a physical iOS device build can be packaged')
    executable = info.get('CFBundleExecutable')
    if not executable or pathlib.Path(executable).name != executable or not (app / executable).is_file():
        parser.error('The app executable is missing or invalid')
    if not args.notices.is_dir() or not any(args.notices.iterdir()):
        parser.error('Third-party license notices are required')
    if shutil.which('ditto') is None:
        parser.error('Run this packaging step on macOS (ditto required)')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='together-ipa-') as directory:
        payload = pathlib.Path(directory) / 'Payload'
        payload.mkdir()
        packaged = payload / app.name
        shutil.copytree(app, packaged, symlinks=True)
        shutil.copytree(args.notices, packaged / 'ThirdPartyNotices', dirs_exist_ok=True)
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent',
                        str(payload), str(output)], check=True)
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('IPA archive integrity check failed')
        if f'Payload/{app.name}/{executable}' not in archive.namelist():
            raise RuntimeError('IPA payload executable is missing')
    print(f'Unsigned IPA created: {output.name}. Requires device-compatible signing before installation.')


if __name__ == '__main__':
    main()
