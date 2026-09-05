#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

"""Apply fixed-length command-spacing transformations to a local MMDVM_Bridge copy."""

from __future__ import annotations

import argparse
from pathlib import Path


class PatchError(RuntimeError):
    pass


PATCHES = (
    (
        "P25 TalkGroup spacing",
        b"REMOTE@%s:%d!TalkGroup%d\x00\x00",
        b"REMOTE@%s:%d!TalkGroup %d\x00",
    ),
    (
        "YSF five-digit Link spacing",
        b"REMOTE@%s:%d!Link%c%c%c%05d\x00\x00",
        b"REMOTE@%s:%d!Link%c%c%c %05d\x00",
    ),
)


def patch_binary(data: bytes) -> bytes:
    original_size = len(data)
    for description, old, new in PATCHES:
        if len(old) != len(new):
            raise PatchError(f"internal fixed-length patch error: {description}")
        old_count = data.count(old)
        new_count = data.count(new)
        if old_count == 1 and new_count == 0:
            data = data.replace(old, new, 1)
        elif old_count == 0 and new_count == 1:
            continue
        else:
            raise PatchError(
                f"unsupported or ambiguous {description} pattern "
                f"(unpatched={old_count}, patched={new_count})"
            )
    if len(data) != original_size:
        raise PatchError("binary size changed")
    return data


def patch_file(path: Path) -> None:
    original = path.read_bytes()
    patched = patch_binary(original)
    if patched != original:
        path.write_bytes(patched)


def main() -> int:
    parser = argparse.ArgumentParser(description="Patch a temporary MMDVM_Bridge copy")
    parser.add_argument("--binary", required=True, type=Path)
    args = parser.parse_args()
    if not args.binary.is_file() or args.binary.is_symlink():
        parser.error("--binary must be a regular, non-symlink file")
    try:
        patch_file(args.binary)
    except PatchError as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
