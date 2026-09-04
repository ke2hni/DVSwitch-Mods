#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

"""Apply architecture-aware command-spacing repairs to MMDVM_Bridge."""

from __future__ import annotations

import argparse
from pathlib import Path
import struct


class PatchError(RuntimeError):
    pass


ELF_MACHINES = {
    3: "i386",
    40: "armhf",
    62: "amd64",
    183: "arm64",
}

P25_PADDED_OLD = b"REMOTE@%s:%d!TalkGroup%d\x00\x00"
P25_PADDED_NEW = b"REMOTE@%s:%d!TalkGroup %d\x00"
P25_TIGHT_OLD = b"REMOTE@%s:%d!TalkGroup%d\x00"

YSF_PADDED_OLD = b"REMOTE@%s:%d!Link%c%c%c%05d\x00\x00"
YSF_PADDED_NEW = b"REMOTE@%s:%d!Link%c%c%c %05d\x00"
YSF_TIGHT_OLD = b"REMOTE@%s:%d!Link%c%c%c%05d\x00"
YSF_TIGHT_NEW = b"REMOTE@%s:%d!Link%c%c%c%06d\x00"


def elf_architecture(data: bytes) -> str:
    if len(data) < 20 or data[:4] != b"\x7fELF":
        raise PatchError("not an ELF executable")
    if data[5] != 1:
        raise PatchError("only little-endian ELF executables are supported")
    machine = struct.unpack_from("<H", data, 18)[0]
    try:
        return ELF_MACHINES[machine]
    except KeyError as exc:
        raise PatchError(f"unsupported ELF machine {machine}") from exc


def replace_exact(data: bytes, description: str, old: bytes, new: bytes) -> bytes:
    if len(old) != len(new):
        raise PatchError(f"internal fixed-length patch error: {description}")
    old_count = data.count(old)
    new_count = data.count(new)
    if old_count == 1 and new_count == 0:
        return data.replace(old, new, 1)
    if old_count == 0 and new_count == 1:
        return data
    raise PatchError(
        f"unsupported or ambiguous {description} pattern "
        f"(unpatched={old_count}, patched={new_count})"
    )


def patch_binary(data: bytes) -> bytes:
    original_size = len(data)
    architecture = elf_architecture(data)

    if architecture in {"arm64", "armhf"}:
        data = replace_exact(
            data, "P25 TalkGroup spacing", P25_PADDED_OLD, P25_PADDED_NEW
        )
    elif data.count(P25_TIGHT_OLD) != 1:
        raise PatchError(
            "unsupported or ambiguous tight-layout P25 TalkGroup pattern "
            f"(unpatched={data.count(P25_TIGHT_OLD)})"
        )

    if architecture == "arm64":
        data = replace_exact(
            data, "YSF five-digit Link spacing", YSF_PADDED_OLD, YSF_PADDED_NEW
        )
    else:
        data = replace_exact(
            data, "YSF five-digit Link width", YSF_TIGHT_OLD, YSF_TIGHT_NEW
        )

    if len(data) != original_size:
        raise PatchError("binary size changed")
    return data


def patch_file(path: Path) -> None:
    original = path.read_bytes()
    patched = patch_binary(original)
    if patched != original:
        path.write_bytes(patched)


def report(data: bytes) -> str:
    architecture = elf_architecture(data)
    if data.count(P25_PADDED_NEW) == 1:
        p25 = "installed"
    elif architecture in {"amd64", "i386"} and data.count(P25_TIGHT_OLD) == 1:
        p25 = "pending tight-layout repair"
    else:
        p25 = "unsupported state"
    if data.count(YSF_PADDED_NEW) == 1 or data.count(YSF_TIGHT_NEW) == 1:
        ysf = "installed"
    else:
        ysf = "unsupported state"
    return f"Architecture: {architecture}\nP25 spacing: {p25}\nYSF five-digit repair: {ysf}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Patch a temporary MMDVM_Bridge copy")
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--report", action="store_true")
    args = parser.parse_args()
    if not args.binary.is_file() or args.binary.is_symlink():
        parser.error("--binary must be a regular, non-symlink file")
    try:
        patch_file(args.binary)
        if args.report:
            print(report(args.binary.read_bytes()))
    except PatchError as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
