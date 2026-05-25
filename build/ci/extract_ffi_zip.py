#!/usr/bin/env python3
"""Extract FFI release zip; tolerates Windows backslash path separators in entries."""
from __future__ import annotations

import os
import sys
import zipfile


def extract_zip(src: str, dest: str) -> None:
    os.makedirs(dest, exist_ok=True)
    with zipfile.ZipFile(src) as zf:
        for info in zf.infolist():
            name = info.filename.replace("\\", "/")
            if not name or name.endswith("/"):
                os.makedirs(os.path.join(dest, name), exist_ok=True)
                continue
            target = os.path.join(dest, *name.split("/"))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with zf.open(info) as src_f, open(target, "wb") as out:
                out.write(src_f.read())


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <zip> <dest-dir>", file=sys.stderr)
        return 2
    extract_zip(sys.argv[1], sys.argv[2])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
