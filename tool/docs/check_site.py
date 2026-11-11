#!/usr/bin/env python3
"""Check the published documentation tree for scope and content leaks."""

from __future__ import annotations

import json
import sys
from pathlib import Path


ALLOWED_TOP_LEVEL = {
    "index.html",
    "404.html",
    "search.json",
    "sitemap.xml",
    "assets",
    "images",
    "stylesheets",
    "getting-started",
    "guides",
    "reference",
    "contributing",
}
ALLOWED_SEARCH_PREFIXES = (
    "getting-started/",
    "guides/",
    "reference/",
    "contributing/",
)
FORBIDDEN_MARKERS = (b"docs/handoffs", b"docs/reviews")


def main() -> int:
    if len(sys.argv) not in (2, 3) or sys.argv[2:] not in ([], ["--final"]):
        print("usage: check_site.py SITE [--final]", file=sys.stderr)
        return 2

    site = Path(sys.argv[1])
    final = len(sys.argv) == 3
    errors: list[str] = []
    if not site.is_dir():
        print(f"site directory does not exist: {site}", file=sys.stderr)
        return 2

    for entry in sorted(site.iterdir()):
        if entry.name not in ALLOWED_TOP_LEVEL:
            errors.append(f"unexpected top-level entry: {entry.name}")

    search_path = site / "search.json"
    if search_path.is_file():
        try:
            items = json.loads(search_path.read_text(encoding="utf-8"))["items"]
        except (OSError, KeyError, TypeError, ValueError) as exc:
            errors.append(f"could not read search.json: {exc}")
        else:
            for item in items:
                location = item.get("location", "")
                if (
                    location != ""
                    and not location.startswith("#")
                    and not location.startswith(ALLOWED_SEARCH_PREFIXES)
                ):
                    errors.append(f"search.json location outside published pages: {location}")

    markers = list(FORBIDDEN_MARKERS)
    if final:
        markers.append(b"placeholder-16x9")
    for path in sorted(p for p in site.rglob("*") if p.is_file()):
        try:
            data = path.read_bytes()
        except OSError as exc:
            errors.append(f"could not read {path.relative_to(site)}: {exc}")
            continue
        for marker in markers:
            if marker in data:
                errors.append(f"{marker.decode()} found in {path.relative_to(site)}")

    if errors:
        print("documentation site check failed:")
        print("\n".join(f"- {error}" for error in errors))
        return 1
    print(f"documentation site check passed: {site}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
