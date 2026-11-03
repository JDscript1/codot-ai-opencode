#!/usr/bin/env python3
"""Build the offline runtime package set embedded in the Android editor.

The APK owns the archives. Device installation never contacts npm, GitHub,
Debian mirrors or nodejs.org: Linux is extracted from the existing rootfs
asset, Node/Pi are unpacked from the pinned archives and the Debian packages
come from a local apt repository generated here.
"""
import argparse
import hashlib
import json
import lzma
import re
import shutil
import tarfile
import time
import urllib.request
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ASSET_PREFIX = "godot_ai/packages"
DEPENDENCY_RE = re.compile(
    r"^\s*([a-z0-9][a-z0-9+.-]*)(?::[a-zA-Z0-9-]+)?\s*"
    r"(?:\(\s*(<<|<=|=|>=|>>|<|>)\s*([^)]+?)\s*\))?\s*$"
)


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            value.update(block)
    return value.hexdigest()


def download(path, spec):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and path.stat().st_size == spec["size"] and digest(path) == spec["sha256"]:
        return path
    partial = path.with_name(path.name + ".part")
    for attempt in range(3):
        try:
            request = urllib.request.Request(spec["url"], headers={"User-Agent": "GodotAIAndroidPackages/1"})
            with urllib.request.urlopen(request, timeout=180) as response, partial.open("wb") as target:
                shutil.copyfileobj(response, target)
            if partial.stat().st_size != spec["size"] or digest(partial) != spec["sha256"]:
                raise RuntimeError(f"Package checksum mismatch: {spec['url']}")
            partial.replace(path)
            return path
        except Exception:
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)
        finally:
            partial.unlink(missing_ok=True)
    return path


def deb822(text):
    records = []
    current = {}
    key = None
    for line in text.splitlines():
        if not line.strip():
            if current:
                records.append(current)
            current, key = {}, None
        elif line[:1] in (" ", "\t") and key:
            current[key] += "\n" + line[1:]
        elif ":" in line:
            key, value = line.split(":", 1)
            current[key.strip()] = value.strip()
    if current:
        records.append(current)
    return records


def _order(character):
    if not character:
        return 0
    if character.isdigit():
        return 0
    if character.isalpha():
        return ord(character)
    if character == "~":
        return -1
    return ord(character) + 256


def _version_part(first, second):
    while first or second:
        while (first and not first[0].isdigit()) or (second and not second[0].isdigit()):
            difference = _order(first[:1]) - _order(second[:1])
            if difference:
                return difference
            first, second = first[1:], second[1:]
        while first[:1] == "0":
            first = first[1:]
        while second[:1] == "0":
            second = second[1:]
        digits_a = re.match(r"\d*", first).group(0)
        digits_b = re.match(r"\d*", second).group(0)
        if len(digits_a) != len(digits_b):
            return len(digits_a) - len(digits_b)
        if digits_a != digits_b:
            return -1 if digits_a < digits_b else 1
        first, second = first[len(digits_a):], second[len(digits_b):]
    return 0


def compare_versions(first, second):
    def split(value):
        epoch, _, rest = value.partition(":")
        if not _:
            epoch, rest = "0", value
        upstream, separator, revision = rest.rpartition("-")
        if not separator:
            upstream, revision = rest, ""
        return int(epoch or 0), upstream, revision

    epoch_a, upstream_a, revision_a = split(first)
    epoch_b, upstream_b, revision_b = split(second)
    if epoch_a != epoch_b:
        return -1 if epoch_a < epoch_b else 1
    result = _version_part(upstream_a, upstream_b)
    if result:
        return -1 if result < 0 else 1
    result = _version_part(revision_a, revision_b)
    return 0 if result == 0 else (-1 if result < 0 else 1)


def version_satisfies(version, operation, required):
    if operation is None:
        return True
    comparison = compare_versions(version, required)
    return {
        "<<": comparison < 0,
        "<=": comparison <= 0,
        "=": comparison == 0,
        ">=": comparison >= 0,
        ">>": comparison > 0,
        "<": comparison < 0,
        ">": comparison > 0,
    }[operation]


def dependency_options(value):
    for group in value.split(","):
        alternatives = []
        for alternative in group.split("|"):
            cleaned = re.sub(r"\[[^\]]*\]|<[^>]*>", "", alternative).strip()
            if not cleaned or cleaned.startswith("${"):
                continue
            match = DEPENDENCY_RE.match(cleaned)
            if match:
                alternatives.append((match.group(1), match.group(2), match.group(3)))
        if alternatives:
            yield alternatives


class PackageIndex:
    def __init__(self, records, installed):
        self.records = {}
        self.provides = {}
        self.installed = installed
        for record in records:
            name = record.get("Package", "")
            if not name:
                continue
            version = record.get("Version", "0")
            previous = self.records.get(name)
            if previous is None or compare_versions(version, previous.get("Version", "0")) > 0:
                self.records[name] = record
            for provided in record.get("Provides", "").split(","):
                virtual = provided.strip().split(" ", 1)[0].split("(", 1)[0].strip()
                if virtual:
                    self.provides.setdefault(virtual, []).append(record)

    def candidate(self, name, operation, required):
        if name in self.installed:
            if version_satisfies(self.installed[name], operation, required):
                return None
        choices = ([self.records[name]] if name in self.records else []) + self.provides.get(name, [])
        for record in choices:
            if version_satisfies(record.get("Version", "0"), operation, required):
                return record
        return None


def resolve(index, requested):
    selected = {}

    def visit(options, parent):
        for name, operation, required in options:
            if index.candidate(name, operation, required) is None:
                if name in index.installed and version_satisfies(index.installed[name], operation, required):
                    return
                continue
            record = index.candidate(name, operation, required)
            package = record["Package"]
            if package in selected:
                return
            selected[package] = record
            for field in ("Pre-Depends", "Depends"):
                for children in dependency_options(record.get(field, "")):
                    visit(children, f"{parent} -> {package}")
            return
        raise RuntimeError(f"Unresolved dependency for {parent}: {' | '.join(item[0] for item in options)}")

    for package in requested:
        visit([(package, None, None)], "requested")
    return [selected[name] for name in sorted(selected)]


def installed_packages(rootfs):
    try:
        with tarfile.open(rootfs, "r:*") as archive:
            member = next(
                (item for item in archive if item.name.lstrip("./") == "var/lib/dpkg/status"),
                None,
            )
            if member is None:
                raise RuntimeError("Debian status file is absent from the rootfs")
            stream = archive.extractfile(member)
            if stream is None:
                raise RuntimeError("Debian status file cannot be read")
            text = stream.read().decode("utf-8", "replace")
    except tarfile.TarError as error:
        raise RuntimeError("Debian rootfs archive is invalid") from error
    installed = {}
    for record in deb822(text):
        if "installed" not in record.get("Status", "").split():
            continue
        if record.get("Architecture") not in ("arm64", "all"):
            continue
        installed[record["Package"]] = record.get("Version", "0")
    return installed


def rootfs_source(work, lock):
    path = work / "downloads" / ("debian-" + lock["sha256"][:16] + ".tar.gz")
    return download(path, {
        "url": lock["url"],
        "size": lock["size"],
        "sha256": lock["sha256"],
    })


def index_source(work, debian):
    name = f"Packages-{debian['suite']}-{debian['architecture']}.xz"
    path = work / "downloads" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    url = f"{debian['repository']}/dists/{debian['suite']}/{debian['component']}/binary-{debian['architecture']}/Packages.xz"
    if not path.is_file():
        partial = path.with_name(path.name + ".part")
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "GodotAIAndroidPackages/1"})
            with urllib.request.urlopen(request, timeout=180) as response, partial.open("wb") as target:
                shutil.copyfileobj(response, target)
            partial.replace(path)
        finally:
            partial.unlink(missing_ok=True)
    with lzma.open(path, "rt", encoding="utf-8") as stream:
        return deb822(stream.read())


def package_stanza(record, filename, size, sha256):
    values = dict(record)
    values["Filename"] = "./" + filename
    values["Size"] = str(size)
    values["SHA256"] = sha256
    preferred = [
        "Package", "Version", "Architecture", "Multi-Arch", "Maintainer", "Installed-Size",
        "Pre-Depends", "Depends", "Provides", "Section", "Priority", "Filename",
        "Size", "SHA256", "Description", "Homepage",
    ]
    output = []
    for key in preferred:
        if key not in values:
            continue
        lines = values[key].splitlines() or [""]
        output.append(f"{key}: {lines[0]}")
        output.extend(" " + line for line in lines[1:])
    return "\n".join(output) + "\n"


def build_debian_zip(work, output, records, debian):
    cache = work / "downloads/debs"
    cache.mkdir(parents=True, exist_ok=True)
    stanzas = []
    files = []
    total = 0
    for record in records:
        filename = Path(record["Filename"]).name
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9+._~:-]{0,240}\.deb", filename):
            raise RuntimeError(f"Unsafe Debian package filename: {filename}")
        path = cache / filename
        spec = {
            "url": f"{debian['repository']}/{record['Filename']}",
            "size": int(record["Size"]),
            "sha256": record["SHA256"],
        }
        download(path, spec)
        total += path.stat().st_size
        if total > 512 * 1024 * 1024:
            raise RuntimeError("Offline Debian package set exceeds the APK budget")
        stanzas.append(package_stanza(record, filename, path.stat().st_size, spec["sha256"]))
        files.append((filename, path))
    target = output / ASSET_PREFIX / debian["asset"]
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_name(target.name + ".part")
    try:
        packages_data = "\n".join(stanzas).encode("utf-8")
        release_data = (
            "Origin: Godot AI Offline\n"
            "Label: Godot AI Offline\n"
            "Suite: stable\n"
            "Codename: godot-ai-offline\n"
            "Architectures: arm64\n"
            "Components: main\n"
            "Date: Thu, 01 Jan 1980 00:00:00 UTC\n"
            "Description: Runtime packages bundled with Godot AI for personal use\n"
            f"SHA256:\n {hashlib.sha256(packages_data).hexdigest()} {len(packages_data)} Packages\n"
        ).encode("utf-8")
        with zipfile.ZipFile(partial, "w", allowZip64=True) as archive:
            packages = zipfile.ZipInfo("Packages", (1980, 1, 1, 0, 0, 0))
            packages.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(packages, packages_data)
            release = zipfile.ZipInfo("Release", (1980, 1, 1, 0, 0, 0))
            release.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(release, release_data)
            for filename, path in files:
                entry = zipfile.ZipInfo(filename, (1980, 1, 1, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_STORED
                entry.external_attr = 0o100644 << 16
                with path.open("rb") as source, archive.open(entry, "w", force_zip64=True) as sink:
                    shutil.copyfileobj(source, sink)
        partial.replace(target)
    finally:
        partial.unlink(missing_ok=True)
    return target


def asset_entry(path, purpose):
    return {
        "name": path.name,
        "size": path.stat().st_size,
        "sha256": digest(path),
        "purpose": purpose,
    }


def copy_verified(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_name(target.name + ".part")
    try:
        shutil.copyfile(source, partial)
        if partial.stat().st_size != source.stat().st_size or digest(partial) != digest(source):
            raise RuntimeError(f"Copied package differs from its verified source: {target.name}")
        partial.replace(target)
    finally:
        partial.unlink(missing_ok=True)
    return target


def build(work, output, distribution):
    if distribution not in ("standard", "ziva-preview"):
        raise ValueError("Unknown package distribution")
    spec = json.loads((HERE / "packages.json").read_text())
    if spec.get("schema") != 1:
        raise RuntimeError("Unsupported package lock schema")
    output = output.resolve()
    package_dir = output / ASSET_PREFIX
    package_dir.mkdir(parents=True, exist_ok=True)
    downloads = work / "downloads/packages"
    assets = []
    versions = {}

    for key in ("node", "pi"):
        component = spec[key]
        source = download(downloads / component["asset"], component)
        copy_verified(source, package_dir / component["asset"])
        versions[key] = component["version"]
        assets.append(asset_entry(package_dir / component["asset"], key))

    rootfs_lock = json.loads((HERE / "rootfs.json").read_text())
    rootfs = rootfs_source(work, rootfs_lock)
    installed = installed_packages(rootfs)
    records = index_source(work, spec["debian"])
    index = PackageIndex(records, installed)
    requested = list(spec["debian"]["packages"])
    if distribution == "ziva-preview":
        requested += spec["debian"]["ziva_packages"]
    selected = resolve(index, requested)
    debian_archive = build_debian_zip(work, output, selected, spec["debian"])
    assets.append(asset_entry(debian_archive, "debian"))
    versions["debian"] = {
        "suite": spec["debian"]["suite"],
        "packages": {record["Package"]: record["Version"] for record in selected},
    }

    ziva_manifest = None
    if distribution == "ziva-preview":
        ziva_manifest = {}
        for key in ("addon", "runtime", "godot"):
            component = spec["ziva"][key]
            source = download(downloads / component["asset"], component)
            copy_verified(source, package_dir / component["asset"])
            ziva_manifest[key] = {
                "version": component["version"],
                "asset": component["asset"],
                "size": component["size"],
                "sha256": component["sha256"],
            }
            assets.append(asset_entry(package_dir / component["asset"], "ziva-" + key))
        versions["ziva"] = spec["ziva"]["addon"]["version"]
        versions["godot"] = spec["ziva"]["godot"]["version"]

    manifest = {
        "schema": 1,
        "distribution": distribution,
        "versions": versions,
        "node": {
            "version": spec["node"]["version"],
            "asset": spec["node"]["asset"],
            "guest_directory": spec["node"]["guest_directory"],
            "strip_components": spec["node"]["strip_components"],
        },
        "pi": {
            "version": spec["pi"]["version"],
            "asset": spec["pi"]["asset"],
            "guest_directory": spec["pi"]["guest_directory"],
            "strip_components": spec["pi"]["strip_components"],
        },
        "debian": {
            "asset": spec["debian"]["asset"],
            "suite": spec["debian"]["suite"],
            "packages": [record["Package"] for record in selected],
        },
        "ziva": ziva_manifest,
        "assets": assets,
    }
    manifest_path = package_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps(manifest, sort_keys=True), flush=True)
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--distribution", choices=("standard", "ziva-preview"), required=True)
    args = parser.parse_args()
    build(args.work.resolve(), args.output.resolve(), args.distribution)


if __name__ == "__main__":
    main()
