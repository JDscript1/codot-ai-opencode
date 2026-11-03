#!/usr/bin/env python3
"""Repackage a pinned official Debian layer for native, shell-free Android extraction.

The ZIP contains regular-file bytes and a manifest for directories/links/modes.
No tar executable, Termux, Python or package manager is needed to install it.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import shutil
import tarfile
import tempfile
import urllib.request
import zipfile

HERE = Path(__file__).resolve().parent


def clean_path(name):
    if '\x00' in name or '\\' in name or name.startswith('/'):
        raise ValueError(f'Invalid archive path: {name!r}')
    name = name.rstrip('/')
    while name.startswith('./'):
        name = name[2:]
    if name in ['', '.']:
        return ''
    if any(part in ['', '.', '..'] for part in name.split('/')):
        raise ValueError(f'Invalid archive path: {name!r}')
    return name


def link_target(path, target):
    if '\x00' in target or '\\' in target or not target:
        raise ValueError('Invalid link target')
    normalized = posixpath.normpath(target.lstrip('/') if target.startswith('/') else posixpath.join(posixpath.dirname(path), target))
    if normalized == '..' or normalized.startswith('../'):
        raise ValueError('Link escapes the guest root')
    # Absolute guest paths must become root-relative host symlinks.
    return posixpath.relpath(normalized, posixpath.dirname(path) or '.')


def info(name):
    entry = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
    entry.compress_type = zipfile.ZIP_DEFLATED
    entry.external_attr = 0o100600 << 16
    return entry


def package(source, output, spec):
    entries = {}
    expanded = 0
    output.parent.mkdir(parents=True, exist_ok=True)
    partial = output.with_suffix('.zip.part')
    try:
        with tarfile.open(source, 'r:*') as archive, zipfile.ZipFile(partial, 'w', compresslevel=6) as target:
            members = {}
            for member in archive:
                name = clean_path(member.name)
                if not name:
                    continue
                if name in entries:
                    raise ValueError(f'Duplicate rootfs member: {name}')
                if len(entries) >= spec['max_entries']:
                    raise ValueError('Too many rootfs members')
                record = {'path': name, 'mode': member.mode & 0o777}
                if member.isdir():
                    record['type'] = 'directory'
                elif member.issym():
                    record.update(type='symlink', target=link_target(name, member.linkname))
                elif member.isfile() or member.islnk():
                    original = members.get(clean_path(member.linkname)) if member.islnk() else member
                    if original is None or not original.isfile():
                        raise ValueError('Unresolved rootfs hardlink')
                    expanded += original.size
                    if expanded > spec['max_unpacked_bytes'] or original.size > 128 * 1024 * 1024:
                        raise ValueError('Rootfs exceeds the unpacking budget')
                    digest = hashlib.sha256()
                    with archive.extractfile(original) as stream, target.open(info('files/' + name), 'w') as sink:
                        count = 0
                        while block := stream.read(1024 * 1024):
                            digest.update(block)
                            sink.write(block)
                            count += len(block)
                    if count != original.size:
                        raise ValueError('Truncated rootfs member')
                    record.update(type='file', size=count, sha256=digest.hexdigest())
                else:
                    # Device nodes must come from explicit host /dev bindings, never extraction.
                    raise ValueError(f'Unsupported rootfs member: {name}')
                entries[name] = record
                members[name] = member
            for name in entries:
                parent = PurePosixPath(name).parent
                while str(parent) != '.':
                    if entries.get(str(parent), {}).get('type') == 'symlink':
                        raise ValueError('Archive writes through a symlink')
                    parent = parent.parent
            manifest = {key: spec[key] for key in ['distribution', 'release', 'architecture', 'source_commit', 'source_repository']}
            manifest.update(schema=1, source_sha256=spec['sha256'], unpacked_bytes=expanded, entries=list(entries.values()))
            target.writestr(info('manifest.json'), json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode())
        partial.replace(output)
    finally:
        partial.unlink(missing_ok=True)
    return manifest


def build(work, output):
    spec = json.loads((HERE / 'rootfs.json').read_text())
    work.mkdir(parents=True, exist_ok=True)
    source = work / ('debian-' + spec['sha256'][:16] + '.tar.gz')
    if not source.exists():
        partial = source.with_suffix('.part')
        try:
            req = urllib.request.Request(spec['url'], headers={'User-Agent': 'GodotLinuxRuntimeBuild/1'})
            with urllib.request.urlopen(req, timeout=90) as response, partial.open('wb') as stream:
                shutil.copyfileobj(response, stream)
            if partial.stat().st_size != spec['size'] or hashlib.file_digest(partial.open('rb'), 'sha256').hexdigest() != spec['sha256']:
                raise ValueError('Rootfs download hash/size mismatch')
            partial.replace(source)
        finally:
            partial.unlink(missing_ok=True)
    if hashlib.file_digest(source.open('rb'), 'sha256').hexdigest() != spec['sha256']:
        raise ValueError('Cached rootfs hash mismatch')
    archive = output / 'assets/godot_ai/linux/rootfs.zip'
    manifest = package(source, archive, spec)
    receipt = {key: manifest[key] for key in ['schema', 'distribution', 'release', 'architecture', 'source_sha256', 'unpacked_bytes']}
    receipt.update(sha256=hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest(), size=archive.stat().st_size, entries=len(manifest['entries']))
    (archive.parent / 'package.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    build(args.work.resolve(), args.output.resolve())


if __name__ == '__main__':
    main()
