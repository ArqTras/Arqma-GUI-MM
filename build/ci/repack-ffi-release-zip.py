#!/usr/bin/env python3
"""Repack FFI release zip with POSIX path separators (ArqTras/FFI layout)."""
from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile
import zipfile

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)
from extract_ffi_zip import extract_zip  # noqa: E402


def pack_platform(staging: str, platform: str, out_zip: str) -> None:
    root = os.path.join(staging, platform)
    if not os.path.isdir(root):
        raise FileNotFoundError(f"missing platform folder after extract: {root}")
    with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED) as zf:
        for dirpath, _, files in os.walk(root):
            for name in files:
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, staging).replace("\\", "/")
                zf.write(path, rel)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input_zip")
    ap.add_argument("output_zip")
    ap.add_argument("platform", help="e.g. linux-x86_64, windows-x86_64-gnu")
    args = ap.parse_args()

    with tempfile.TemporaryDirectory(prefix="ffi-repack-") as tmp:
        extract_zip(args.input_zip, tmp)
        plat_root = os.path.join(tmp, args.platform)
        if not os.path.isdir(plat_root):
            wrapped = os.path.join(tmp, args.platform)
            os.makedirs(wrapped, exist_ok=True)
            for entry in os.listdir(tmp):
                if entry == args.platform:
                    continue
                shutil.move(os.path.join(tmp, entry), wrapped)
        if os.path.isfile(args.output_zip):
            os.remove(args.output_zip)
        pack_platform(tmp, args.platform, args.output_zip)
    print(f"repacked -> {args.output_zip}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
