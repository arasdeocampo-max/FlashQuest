"""Report exact APK bytes and ZIP contents using only the Python standard library.

Usage: python tool/apk_size_report.py path/to/apk [path/to/another.apk ...]
"""

import hashlib
import json
from pathlib import Path
import sys
import zipfile


def inspect_apk(path):
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        groups = {}
        for entry in entries:
            if entry.filename.startswith("lib/"):
                group = "/".join(entry.filename.split("/")[:2])
            elif entry.filename.startswith("assets/"):
                group = "assets"
            elif entry.filename.endswith(".dex"):
                group = "dex"
            else:
                group = "resources_and_metadata"
            groups[group] = groups.get(group, 0) + entry.compress_size

        def describe(entry):
            return {
                "name": entry.filename,
                "uncompressed_bytes": entry.file_size,
                "packaged_bytes": entry.compress_size,
            }

        size = path.stat().st_size
        with path.open("rb") as source:
            digest = hashlib.file_digest(source, "sha256").hexdigest()
        return {
            "path": str(path.resolve()),
            "bytes": size,
            "MiB": round(size / 1024**2, 4),
            "sha256": digest,
            "packaged_bytes_by_group": groups,
            "zip_headers_alignment_and_signing_bytes": size - sum(groups.values()),
            "native_libraries": [describe(e) for e in entries if e.filename.endswith(".so")],
            "largest_entries": [
                describe(e)
                for e in sorted(entries, key=lambda e: e.compress_size, reverse=True)[:15]
            ],
        }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    print(json.dumps([inspect_apk(Path(p)) for p in sys.argv[1:]], indent=2))
