#!/usr/bin/env python3
"""Generate Android native-runtime license assets from a resolved Gradle graph.

The input is the actual ``releaseRuntimeClasspath`` dependency report. Maven
POM license metadata is required for every resolved external module. The only
exception is Flutter's locally published engine artifacts, whose POMs do not
carry license metadata; those are covered by the exact Flutter SDK LICENSE
file selected by ``--flutter-root``. Unknown metadata fails closed instead of
guessing a common license.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from urllib.parse import urlparse


MAX_DOCUMENT_BYTES = 2 * 1024 * 1024
MAX_TREE_BYTES = 16 * 1024 * 1024
MAX_DOCUMENTS = 4096
COORDINATE = re.compile(
    r"(?<![A-Za-z0-9_.-])"
    r"(?P<group>[A-Za-z0-9_][A-Za-z0-9_.-]*):"
    r"(?P<artifact>[A-Za-z0-9_][A-Za-z0-9_.-]*):"
    r"(?P<version>[A-Za-z0-9][A-Za-z0-9_.+\-]*)"
)
XML_NS = {"m": "http://maven.apache.org/POM/4.0.0"}
ARTIFACT_NOTICE = re.compile(
    r"(?:^|/)NOTICE(?:\.[A-Za-z0-9._-]+)?$",
    re.IGNORECASE,
)
URL = re.compile(r"https?://[^\s)<>]+")
MOZILLA_MPL_PLAINTEXT_URL = "https://www.mozilla.org/media/MPL/2.0/index.txt"


class GenerationError(RuntimeError):
    pass


def parse_report(text: str) -> list[tuple[str, str, str]]:
    """Return unique resolved external coordinates from Gradle's report."""
    coordinates: set[tuple[str, str, str]] = set()
    for line in text.splitlines():
        # ``project :foo`` entries are not published runtime coordinates.
        if "project :" in line:
            continue
        matches = list(COORDINATE.finditer(line))
        if not matches:
            continue
        match = matches[-1]
        group = match.group("group")
        artifact = match.group("artifact")
        version = match.group("version")
        # A report line with ``requested -> resolved`` is represented by its
        # final coordinate, which is the one Gradle actually selected.
        resolved = re.search(
            r"->\s*(?P<version>[A-Za-z0-9][A-Za-z0-9_.+\-]*)",
            line[match.end() :],
        )
        if resolved:
            version = resolved.group("version")
        coordinates.add((group, artifact, version))
    if not coordinates:
        raise GenerationError("No external coordinates found in dependency report.")
    return sorted(coordinates)


def locate_pom(cache_roots: list[Path], group: str, artifact: str, version: str) -> Path:
    filename = f"{artifact}-{version}.pom"
    candidates: list[Path] = []
    for root in cache_roots:
        for relative in (
            Path(group) / artifact / version,
            Path(*group.split(".")) / artifact / version,
        ):
            directory = root / relative
            candidates.extend(directory.glob(f"*/{filename}"))
            # A repository root can also be supplied directly rather than the
            # Gradle module cache layout.
            direct = root / relative / filename
            if direct.is_file():
                candidates.append(direct)
    if not candidates:
        raise GenerationError(
            f"Resolved dependency has no cached POM: {group}:{artifact}:{version}"
        )
    return sorted(set(candidates))[0]


def locate_jar(
    cache_roots: list[Path], group: str, artifact: str, version: str
) -> Path | None:
    filename = f"{artifact}-{version}.jar"
    candidates: list[Path] = []
    for root in cache_roots:
        for relative in (
            Path(group) / artifact / version,
            Path(*group.split(".")) / artifact / version,
        ):
            directory = root / relative
            candidates.extend(directory.glob(f"*/{filename}"))
            direct = root / relative / filename
            if direct.is_file():
                candidates.append(direct)
    return sorted(set(candidates))[0] if candidates else None


def pom_licenses(
    pom: Path,
    cache_roots: list[Path],
    visited: set[Path] | None = None,
) -> list[tuple[str, str]]:
    if visited is None:
        visited = set()
    if pom in visited:
        raise GenerationError(f"Cyclic license metadata parents in {pom.name}.")
    visited.add(pom)
    try:
        root = ET.parse(pom).getroot()
    except (ET.ParseError, OSError) as error:
        raise GenerationError(f"Cannot parse dependency POM {pom.name}: {error}") from error
    licenses = []
    for license_node in root.findall("m:licenses/m:license", XML_NS):
        name = (license_node.findtext("m:name", default="", namespaces=XML_NS) or "").strip()
        url = (license_node.findtext("m:url", default="", namespaces=XML_NS) or "").strip()
        if not name or not url:
            raise GenerationError(f"Incomplete license metadata in {pom.name}.")
        parsed = urlparse(url)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise GenerationError(f"Unsupported license URL in {pom.name}: {url}")
        licenses.append((name, url))
    if not licenses:
        parent = root.find("m:parent", XML_NS)
        if parent is not None:
            group = (parent.findtext("m:groupId", default="", namespaces=XML_NS) or "").strip()
            artifact = (parent.findtext("m:artifactId", default="", namespaces=XML_NS) or "").strip()
            version = (parent.findtext("m:version", default="", namespaces=XML_NS) or "").strip()
            if group and artifact and version:
                parent_pom = locate_pom(cache_roots, group, artifact, version)
                return pom_licenses(parent_pom, cache_roots, visited)
        raise GenerationError(f"Missing license metadata in {pom.name} and its POM parents.")
    return licenses


def safe_name(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._-]+", "_", value).strip("._")
    return value or "license"


def read_utf8(path: Path) -> bytes:
    try:
        data = path.read_bytes()
    except OSError as error:
        raise GenerationError(f"Cannot read license source {path}: {error}") from error
    if not data or len(data) > MAX_DOCUMENT_BYTES:
        raise GenerationError(f"License source has invalid size: {path}")
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise GenerationError(f"License source is not UTF-8: {path}") from error
    return data


def download_license(url: str, cache: Path | None) -> bytes:
    cache_path = None
    if cache is not None:
        cache.mkdir(parents=True, exist_ok=True)
        cache_path = cache / (hashlib.sha256(url.encode("utf-8")).hexdigest() + ".txt")
        if cache_path.is_file():
            return read_utf8(cache_path)
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Lineup Android license asset generator"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read(MAX_DOCUMENT_BYTES + 1)
    except (OSError, urllib.error.URLError) as error:
        raise GenerationError(f"Cannot fetch license metadata text from {url}: {error}") from error
    if not data or len(data) > MAX_DOCUMENT_BYTES:
        raise GenerationError(f"Fetched license text has invalid size: {url}")
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise GenerationError(f"Fetched license text is not UTF-8: {url}") from error
    if cache_path is not None:
        cache_path.write_bytes(data)
    return data


def artifact_notice_documents(
    group: str,
    artifact: str,
    version: str,
    cache_roots: list[Path],
) -> list[tuple[str, str, str, str, bytes]]:
    """Read human-readable NOTICE entries shipped inside a cached artifact JAR."""
    jar = locate_jar(cache_roots, group, artifact, version)
    if jar is None:
        return []
    coordinate = f"{group}:{artifact}:{version}"
    artifact_dir = Path("licenses/artifacts") / (
        f"{safe_name(group)}__{safe_name(artifact)}__{safe_name(version)}"
    )
    documents: list[tuple[str, str, str, str, bytes]] = []
    try:
        with zipfile.ZipFile(jar) as archive:
            for member in archive.infolist():
                if member.is_dir() or not ARTIFACT_NOTICE.search(member.filename):
                    continue
                if member.file_size > MAX_DOCUMENT_BYTES:
                    raise GenerationError(
                        f"Artifact NOTICE is too large: {coordinate}!/{member.filename}"
                    )
                data = archive.read(member)
                if not data or len(data) > MAX_DOCUMENT_BYTES:
                    raise GenerationError(
                        f"Artifact NOTICE has invalid size: {coordinate}!/{member.filename}"
                    )
                try:
                    data.decode("utf-8")
                except UnicodeDecodeError as error:
                    raise GenerationError(
                        f"Artifact NOTICE is not UTF-8: {coordinate}!/{member.filename}"
                    ) from error
                relative = artifact_dir / f"{safe_name(member.filename.replace('/', '__'))}.txt"
                documents.append(
                    (
                        coordinate,
                        f"Artifact notice: {member.filename}",
                        f"jar:{coordinate}!/{member.filename}",
                        relative.as_posix(),
                        data,
                    )
                )
    except (OSError, zipfile.BadZipFile) as error:
        raise GenerationError(f"Cannot read dependency artifact {jar.name}: {error}") from error
    return documents


def referenced_mozilla_license_urls(data: bytes) -> list[str]:
    text = data.decode("utf-8")
    urls = set()
    for raw_url in URL.findall(text):
        url = raw_url.rstrip(".,;)")
        parsed = urlparse(url)
        if "mozilla.org" in parsed.netloc.lower() and "/mpl/2.0" in parsed.path.lower():
            urls.add(url)
    return sorted(urls)


def flutter_root_from_args(value: str | None) -> Path | None:
    if value:
        return Path(value).resolve()
    if os.environ.get("FLUTTER_ROOT"):
        return Path(os.environ["FLUTTER_ROOT"]).resolve()
    flutter = shutil.which("flutter")
    if flutter:
        return Path(flutter).resolve().parent.parent
    return None


def run_gradle_report(project: Path, configuration: str) -> str:
    wrapper = project / "gradlew"
    if not wrapper.is_file():
        raise GenerationError(f"Gradle wrapper not found: {wrapper}")
    command = [
        str(wrapper),
        ":app:dependencies",
        "--configuration",
        configuration,
        "--no-daemon",
    ]
    try:
        result = subprocess.run(
            command,
            cwd=project,
            check=True,
            capture_output=True,
            text=True,
            env={**os.environ, "GRADLE_OPTS": "-Dorg.gradle.daemon=false"},
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise GenerationError(f"Gradle dependency report failed: {error}") from error
    return result.stdout + result.stderr


def write_text(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def generate(
    report: str,
    output: Path,
    cache_roots: list[Path],
    flutter_root: Path | None,
    license_cache: Path | None,
    flutter_version: str,
) -> dict[str, object]:
    coordinates = parse_report(report)
    entries: list[tuple[str, str, str, str, str]] = []
    local_documents: dict[str, bytes] = {}
    # coordinate, license name, URL, relative asset path, sha256
    flutter_coordinates: list[tuple[str, str, str]] = []
    for group, artifact, version in coordinates:
        coordinate = f"{group}:{artifact}:{version}"
        if group == "io.flutter":
            flutter_coordinates.append((group, artifact, version))
            continue
        pom = locate_pom(cache_roots, group, artifact, version)
        for name, url in pom_licenses(pom, cache_roots):
            basename = safe_name(name)
            relative = Path("licenses") / f"{safe_name(group)}__{safe_name(artifact)}" / f"{basename}.txt"
            entries.append((coordinate, name, url, relative.as_posix(), ""))
        for notice_coordinate, name, source, relative, data in artifact_notice_documents(
            group, artifact, version, cache_roots
        ):
            entries.append(
                (
                    notice_coordinate,
                    name,
                    source,
                    relative,
                    hashlib.sha256(data).hexdigest(),
                )
            )
            local_documents[relative] = data
            for url in referenced_mozilla_license_urls(data):
                referenced_relative = (
                    Path(relative).parent / "Mozilla_Public_License_2.0.txt"
                ).as_posix()
                entries.append(
                    (
                        notice_coordinate,
                        (
                            "Referenced Mozilla Public License, v. 2.0 terms; "
                            f"NOTICE reference: {url}; plaintext source: "
                            f"{MOZILLA_MPL_PLAINTEXT_URL}"
                        ),
                        MOZILLA_MPL_PLAINTEXT_URL,
                        referenced_relative,
                        "",
                    )
                )

    if flutter_coordinates:
        if flutter_root is None:
            raise GenerationError(
                "Flutter runtime artifacts have no POM license metadata; pass --flutter-root."
            )
        flutter_license = flutter_root / "LICENSE"
        data = read_utf8(flutter_license)
        relative = Path("licenses/flutter/Flutter-SDK-LICENSE.txt")
        entries.append(
            (
                ", ".join(
                    f"{group}:{artifact}:{version}"
                    for group, artifact, version in flutter_coordinates
                ),
                "Flutter SDK license",
                "Flutter SDK LICENSE file",
                relative.as_posix(),
                hashlib.sha256(data).hexdigest(),
            )
        )
    if not entries:
        raise GenerationError("No license-bearing runtime dependencies were generated.")
    if len(entries) > MAX_DOCUMENTS - 2:
        raise GenerationError("Generated Android license tree exceeds 4096 documents.")

    output.parent.mkdir(parents=True, exist_ok=True)
    staging: Path | None = Path(
        tempfile.mkdtemp(prefix="lineup-android-licenses-", dir=output.parent)
    )
    try:
        total = 0
        seen_paths: set[str] = set()
        summary: list[str] = [
            "Lineup Android release runtime notices",
            "",
            "Generated from the resolved releaseRuntimeClasspath dependency graph.",
            (
                "Each external module below supplied its own Maven POM license "
                "metadata; license text was fetched from that metadata URL. "
                "Flutter engine artifacts use the exact LICENSE file from the "
                "selected Flutter SDK because their POMs do not carry license "
                "metadata. Cached artifact JAR NOTICE entries and referenced "
                "license terms are included with their archive provenance."
            ),
            "",
        ]
        build_info: list[str] = [
            "Lineup Android native runtime license resources",
            f"Flutter version: {flutter_version}",
            f"Resolved releaseRuntimeClasspath modules: {len(coordinates)}",
            "Media3 and other versions are recorded in the dependency entries below.",
            "",
        ]
        dependency_lines: list[str] = []
        for coordinate, name, url, relative, known_hash in sorted(entries):
            if relative in seen_paths:
                continue
            seen_paths.add(relative)
            if relative in local_documents:
                data = local_documents[relative]
            elif url == "Flutter SDK LICENSE file":
                assert flutter_root is not None
                data = read_utf8(flutter_root / "LICENSE")
            else:
                data = download_license(url, license_cache)
            digest = hashlib.sha256(data).hexdigest()
            if known_hash and known_hash != digest:
                raise GenerationError(f"Flutter license hash changed while generating {relative}.")
            total += len(data)
            if total > MAX_TREE_BYTES:
                raise GenerationError("Generated Android license tree exceeds 16 MiB.")
            assert staging is not None
            write_text(staging / relative, data)
            summary.append(f"{coordinate} | {name} | {url} | {relative} | sha256:{digest}")
            dependency_lines.append(f"{coordinate} | {name} | {url} | {relative} | sha256:{digest}")
            build_info.append(f"{coordinate} {name} {url} sha256:{digest}")
        assert staging is not None
        summary_path = staging / "licenses/NOTICES-SUMMARY.txt"
        write_text(summary_path, ("\n".join(summary) + "\n").encode("utf-8"))
        dependency_path = staging / "licenses/DEPENDENCIES.txt"
        write_text(
            dependency_path,
            (
                "Resolved releaseRuntimeClasspath license manifest\n\n"
                + "\n".join(sorted(dependency_lines))
                + "\n"
            ).encode("utf-8"),
        )
        build_info.append("")
        build_info.append(f"Generated license bytes: {total}")
        write_text(staging / "BUILD-INFO.txt", ("\n".join(build_info) + "\n").encode("utf-8"))

        if output.exists():
            shutil.rmtree(output)
        staging.rename(output)
        staging = None
    finally:
        if staging is not None and staging.exists():
            shutil.rmtree(staging)
    return {
        "coordinates": len(coordinates),
        "documents": len(seen_paths) + 2,
        "bytes": total,
        "output": str(output),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dependency-report", type=Path)
    parser.add_argument("--gradle-project", type=Path)
    parser.add_argument("--configuration", default="releaseRuntimeClasspath")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--gradle-cache",
        action="append",
        type=Path,
        default=[Path.home() / ".gradle/caches/modules-2/files-2.1"],
    )
    parser.add_argument("--flutter-root")
    parser.add_argument("--flutter-version", default="unknown")
    parser.add_argument("--license-cache", type=Path)
    args = parser.parse_args()
    if bool(args.dependency_report) == bool(args.gradle_project):
        parser.error("provide exactly one of --dependency-report or --gradle-project")
    try:
        report = (
            args.dependency_report.read_text(encoding="utf-8")
            if args.dependency_report
            else run_gradle_report(args.gradle_project.resolve(), args.configuration)
        )
        result = generate(
            report,
            args.output.resolve(),
            [path.resolve() for path in args.gradle_cache],
            flutter_root_from_args(args.flutter_root),
            args.license_cache.resolve() if args.license_cache else None,
            args.flutter_version,
        )
    except GenerationError as error:
        print(f"generate-licenses: {error}", file=sys.stderr)
        return 1
    print(
        "generated Android license assets: "
        f"{result['coordinates']} modules, {result['documents']} documents, "
        f"{result['bytes']} license bytes at {result['output']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
