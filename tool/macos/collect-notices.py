#!/usr/bin/env python3
"""Generate a component's NOTICES file from the sources it actually compiled.

Run by tool/macos/build-mpv.sh (dist stage). For one component it:

1. finds every file that went into the build: sources and the headers they
   included, from ninja's dependency log (meson and CMake builds), make-style
   dependency files (`*.d`, automake `.deps/*.P[l]o`, Xcode intermediates),
   and the members of static archives, matched to sources by file name;
2. keeps the files inside the component's source tree;
3. extracts each file's leading comment block(s), the license/copyright
   header;
4. reports a header as notice-bearing when it carries permissive license
   terms that require the notice to accompany binaries (BSD/MIT/ISC/Apache/
   zlib/Boost/IJG...) and is not the component's own standard header;
5. writes the distinct texts, each with the files that carry it, to OUT.

It prints one coverage line, and lists any compiled file whose header names
the GNU GPL without the Lesser/Library GPL, so a GPL file would be noticed.

This is an aid for the license review, not a guarantee of completeness:
notices outside a file's leading comments, or in generated files, need review.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

SOURCE_EXTENSIONS = {
    ".c", ".cc", ".cpp", ".cxx", ".m", ".mm", ".s", ".S", ".asm", ".swift",
    ".h", ".hh", ".hpp", ".hxx", ".inc", ".inl", ".def",
}

# Terms whose notice must accompany binary distributions.
PERMISSIVE = re.compile(
    r"Redistribution and use in source and binary forms"
    r"|Permission is hereby granted"
    r"|Permission to use, copy, modify"
    r"|Licensed under the Apache License"
    r"|Apache License,? Version 2\.0"
    r"|Boost Software License"
    r"|This software is provided ['‘]as-is['’]"
    r"|Independent JPEG Group"
    r"|SPDX-License-Identifier:\s*(?:MIT|ISC|BSD|Apache|Zlib|BSL|X11)"
    r"|\bMIT License\b|\bISC License\b|\bBSD[- ]style license\b|\bBSD license\b"
    r"|\b(?:BSD|MIT|ISC|Apache)[- ]licen[sc]ed\b"
    r"|licen[sc]ed under the (?:\S+ ){0,3}(?:BSD|MIT|ISC|Apache|zlib)\b",
    re.IGNORECASE,
)
GPL_ONLY = re.compile(r"GNU General Public License", re.IGNORECASE)
LESSER = re.compile(r"Lesser General Public|Library General Public|LGPL", re.IGNORECASE)
# Bison parser skeletons are GPL with an exception that lets the generated
# parser be distributed under any terms (glslang's glslang_tab.cpp).
BISON_EXCEPTION = re.compile(r"special exception.{0,200}Bison", re.IGNORECASE | re.DOTALL)

# A component's own standard header; such files are covered by the
# component's license file. Copyleft components emit every permissive header.
COMPONENTS = {
    "mpv": {"copyleft": True, "own": []},
    "ffmpeg": {"copyleft": True, "own": []},
    "libplacebo": {"copyleft": True, "own": []},
    "fribidi": {"copyleft": True, "own": []},
    "glslang": {"copyleft": False, "own": []},
    "moltenvk": {"copyleft": False, "own": [r"The Brenwill Workshop"]},
    "openssl": {"copyleft": False, "own": [r"openssl\.org/source/license\.html"]},
    "curl": {"copyleft": False, "own": [r"SPDX-License-Identifier:\s*curl\s*$"]},
    "lcms2": {"copyleft": False, "own": [r"Little Color Management System"]},
    "dav1d": {"copyleft": False, "own": [r"VideoLAN and dav1d authors"]},
    "freetype": {"copyleft": False, "own": [r"FreeType project"]},
    "harfbuzz": {"copyleft": False, "own": [r"This is part of HarfBuzz"]},
    "libass": {"copyleft": False, "own": [r"This file is part of libass"]},
}


def parse_make_deps(path):
    """Prerequisites listed in a make-style dependency file."""
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return []
    text = text.replace("\\\n", " ")
    files = []
    for line in text.splitlines():
        if ":" not in line or line.lstrip().startswith("#"):
            continue
        _, _, deps = line.partition(": ")
        if not deps:
            _, _, deps = line.partition(":")
        # Escaped spaces stay inside one path.
        for token in re.split(r"(?<!\\)\s+", deps.strip()):
            if token:
                files.append(token.replace("\\ ", " "))
    return files


def ninja_files(build):
    """Sources and headers from ninja's dependency log and build graph."""
    files = []
    out = subprocess.run(["ninja", "-C", build, "-t", "deps"], capture_output=True,
                         text=True).stdout
    for line in out.splitlines():
        if line.startswith("    "):
            files.append(line.strip())
    out = subprocess.run(["ninja", "-C", build, "-t", "inputs"], capture_output=True,
                         text=True).stdout
    files += [line.strip() for line in out.splitlines() if line.strip()]
    return files


def archive_members(archive):
    """Object file names in a (possibly universal) static archive."""
    with tempfile.TemporaryDirectory() as tmp:
        thin = os.path.join(tmp, "thin.a")
        result = subprocess.run(["lipo", archive, "-thin", "arm64", "-output", thin],
                                capture_output=True)
        source = thin if result.returncode == 0 else archive
        out = subprocess.run(["ar", "-t", source], capture_output=True, text=True).stdout
    return [m for m in out.split() if m.endswith(".o")]


def collect(build_dirs, archives, source_root):
    found = set()

    def add(path, *bases):
        if not os.path.isabs(path):
            # Relative prerequisites are relative to the directory the
            # compiler ran in: the build root (FFmpeg, OpenSSL, ninja) or the
            # directory holding .deps (automake).
            for base in bases:
                if os.path.exists(os.path.join(base, path)):
                    path = os.path.join(base, path)
                    break
            else:
                return
        path = os.path.realpath(path)
        if path.startswith(source_root + os.sep) and \
                os.path.splitext(path)[1] in SOURCE_EXTENSIONS and os.path.isfile(path):
            found.add(path)

    for build in build_dirs:
        if os.path.isfile(os.path.join(build, "build.ninja")):
            for f in ninja_files(build):
                add(f, build)
        for dirpath, _, names in os.walk(build):
            for name in names:
                if name.endswith((".d", ".Plo", ".Po")):
                    for f in parse_make_deps(os.path.join(dirpath, name)):
                        add(f, build, os.path.dirname(dirpath), dirpath)
    if archives:
        stems = {}
        for dirpath, _, names in os.walk(source_root):
            for name in names:
                stem, ext = os.path.splitext(name)
                if ext in SOURCE_EXTENSIONS - {".h", ".hh", ".hpp", ".hxx"}:
                    stems.setdefault(stem, []).append(os.path.join(dirpath, name))
        for archive in archives:
            for member in archive_members(archive):
                for path in stems.get(os.path.splitext(member)[0], []):
                    add(path, source_root)
    return found


def leading_comments(path):
    """The comment blocks at the top of a source file, markers removed."""
    try:
        text = open(path, encoding="utf-8", errors="replace").read(16384)
    except OSError:
        return ""
    asm = os.path.splitext(path)[1] in {".s", ".S", ".asm"}
    lines = text.splitlines()
    out, i = [], 0
    while i < len(lines):
        stripped = lines[i].strip()
        if not stripped:
            i += 1
            continue
        if stripped.startswith("/*"):
            block = []
            while i < len(lines):
                block.append(lines[i])
                if "*/" in lines[i]:
                    i += 1
                    break
                i += 1
            out += block
        elif stripped.startswith("//") or (asm and stripped.startswith((";", "#", "@"))
                                           and not re.match(r"#\s*(include|if|define)", stripped)):
            out.append(lines[i])
            i += 1
        else:
            break
    cleaned = []
    for line in out:
        line = re.sub(r"^\s*(/\*+|\*+/|\*|//+|;+|#+|@+)", "", line)
        line = re.sub(r"\*+/\s*$", "", line).rstrip()
        cleaned.append(line.strip())
    while cleaned and not cleaned[0]:
        cleaned.pop(0)
    while cleaned and not cleaned[-1]:
        cleaned.pop()
    return "\n".join(cleaned)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--component", required=True, choices=sorted(COMPONENTS))
    parser.add_argument("--source", required=True)
    parser.add_argument("--build", action="append", default=[])
    parser.add_argument("--archive", action="append", default=[])
    parser.add_argument("--out", required=True)
    parser.add_argument("--fail-on-gpl", action="store_true",
                        help="exit non-zero if a compiled file has a GPL-only header")
    args = parser.parse_args()

    config = COMPONENTS[args.component]
    own = [re.compile(p, re.MULTILINE) for p in config["own"]]
    source_root = os.path.realpath(args.source)
    files = sorted(collect([os.path.realpath(b) for b in args.build],
                           [os.path.realpath(a) for a in args.archive], source_root))
    if not files:
        sys.exit(f"collect-notices: no compiled files found for {args.component}")

    notices = {}
    gpl = []
    for path in files:
        header = leading_comments(path)
        rel = os.path.relpath(path, source_root)
        if GPL_ONLY.search(header) and not LESSER.search(header) and \
                not BISON_EXCEPTION.search(header):
            gpl.append(rel)
        if not PERMISSIVE.search(header):
            continue
        if not config["copyleft"] and any(p.search(header) for p in own):
            continue
        notices.setdefault(header, []).append(rel)

    notice_files = sum(len(v) for v in notices.values())
    with open(args.out, "w", encoding="utf-8") as out:
        out.write(f"Notices from the compiled sources of {args.component}\n")
        out.write("Generated by tool/macos/collect-notices.py from the leading license\n"
                  "comments of the files compiled into the Lineup Desktop runtime. The\n"
                  "component's own license file is in this directory. Per-file\n"
                  "completeness remains a legal-review item.\n")
        out.write(f"\n{len(files)} compiled files scanned; {notice_files} carry the "
                  f"{len(notices)} notices below.\n")
        for header, paths in sorted(notices.items(), key=lambda item: sorted(item[1])[0]):
            out.write("\n" + "=" * 78 + "\n")
            out.write("Files: " + ", ".join(sorted(paths)) + "\n\n")
            out.write(header + "\n")
    print(f"notices {args.component}: {len(files)} compiled files scanned, "
          f"{notice_files} with notice-bearing headers, {len(notices)} distinct notices"
          + (f", {len(gpl)} GPL-only headers: {', '.join(gpl)}" if gpl else ""))
    if gpl and args.fail_on_gpl:
        sys.exit(f"collect-notices: {args.component} compiles files with GPL-only headers")


if __name__ == "__main__":
    main()
