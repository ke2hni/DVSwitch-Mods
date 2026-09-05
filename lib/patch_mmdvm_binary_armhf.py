#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

"""Apply hash-specific, fixed-size ARMHF MMDVM_Bridge spacing repairs.

No upstream executable is distributed.  P25 is repaired in place.  The
longer YSF format string is placed in verified padding, the executable
PT_LOAD segment is extended to map it, and its ARM literal is redirected.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path


class PatchError(RuntimeError):
    pass


ORIGINAL_SHA256 = "554721a6006f959fbc9f1ebeca63077e033d944655688fc9a0ae57f2a84a1b5f"
PATCHED_SHA256 = "b896b944eba1cdd6a4517aa5702258675d6184a79940bad965e5f6d559dcce09"
FILE_SIZE = 4_637_356
BUILD_ID = bytes.fromhex("209512bc724cb031f84f1a6f4dace4f90e5466df")

P25_ORIGINAL_OFFSET = 0x88110
P25_ORIGINAL = b"REMOTE@%s:%d!TalkGroup%d\0\0"
P25_REPAIRED = b"REMOTE@%s:%d!TalkGroup %d\0"

YSF_ORIGINAL_OFFSET = 0x8EBD0
YSF_ORIGINAL_ADDRESS = 0x9EBD0
YSF_ORIGINAL = b"REMOTE@%s:%d!Link%c%c%c%05d\0"
YSF_REPAIRED = b"REMOTE@%s:%d!Link%c%c%c %05d\0"
YSF_REFERENCE_OFFSET = 0x69328

PADDING_START = 0x92400
PADDING_END = 0x92E80
YSF_REPAIRED_OFFSET = PADDING_START
YSF_REPAIRED_ADDRESS = 0xA2400
ORIGINAL_SEGMENT_END = 0x92400
REPAIRED_SEGMENT_END = 0x92420

# ELF32 program-header index 3: p_filesz and p_memsz.
LOAD_FILESZ_OFFSET = 0xA4
LOAD_MEMSZ_OFFSET = 0xA8


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PatchError(message)


def expected_padding() -> bytes:
    padding = bytearray(PADDING_END - PADDING_START)
    padding[:len(YSF_REPAIRED)] = YSF_REPAIRED
    return bytes(padding)


def validate_common(data: bytes) -> None:
    require(len(data) == FILE_SIZE, f"unsupported ARMHF file size: {len(data)}")
    require(data[:6] == b"\x7fELF\x01\x01", "not a little-endian ELF32 executable")
    require(struct.unpack_from("<H", data, 0x10)[0] == 2,
            "unsupported ARMHF ELF type (expected executable)")
    require(struct.unpack_from("<H", data, 0x12)[0] == 40,
            "unsupported ELF machine (expected ARM)")
    flags = struct.unpack_from("<I", data, 0x24)[0]
    require(flags == 0x05000400, f"unsupported ARM EABI flags: 0x{flags:08x}")
    require(data.count(BUILD_ID) == 1, "missing or ambiguous expected ARMHF GNU build ID")
    require(data[YSF_ORIGINAL_OFFSET:YSF_ORIGINAL_OFFSET + len(YSF_ORIGINAL)] == YSF_ORIGINAL,
            "unexpected original ARMHF YSF format string")
    require(data.count(YSF_ORIGINAL) == 1, "unexpected original ARMHF YSF string count")


def validate_original(data: bytes) -> None:
    validate_common(data)
    require(data[P25_ORIGINAL_OFFSET:P25_ORIGINAL_OFFSET + len(P25_ORIGINAL)] == P25_ORIGINAL,
            "unexpected original ARMHF P25 format string or padding")
    require(struct.unpack_from("<I", data, LOAD_FILESZ_OFFSET)[0] == ORIGINAL_SEGMENT_END,
            "unexpected original ARMHF executable-segment file size")
    require(struct.unpack_from("<I", data, LOAD_MEMSZ_OFFSET)[0] == ORIGINAL_SEGMENT_END,
            "unexpected original ARMHF executable-segment memory size")
    require(data[PADDING_START:PADDING_END] == bytes(PADDING_END - PADDING_START),
            "ARMHF relocation padding is not entirely zero-filled")
    require(struct.unpack_from("<I", data, YSF_REFERENCE_OFFSET)[0] == YSF_ORIGINAL_ADDRESS,
            "unexpected original ARMHF YSF literal reference")


def validate_repaired(data: bytes) -> None:
    validate_common(data)
    require(data[P25_ORIGINAL_OFFSET:P25_ORIGINAL_OFFSET + len(P25_REPAIRED)] == P25_REPAIRED,
            "unexpected repaired ARMHF P25 format string")
    require(struct.unpack_from("<I", data, LOAD_FILESZ_OFFSET)[0] == REPAIRED_SEGMENT_END,
            "unexpected repaired ARMHF executable-segment file size")
    require(struct.unpack_from("<I", data, LOAD_MEMSZ_OFFSET)[0] == REPAIRED_SEGMENT_END,
            "unexpected repaired ARMHF executable-segment memory size")
    require(data[PADDING_START:PADDING_END] == expected_padding(),
            "relocated ARMHF YSF string or unused padding is invalid")
    require(struct.unpack_from("<I", data, YSF_REFERENCE_OFFSET)[0] == YSF_REPAIRED_ADDRESS,
            "unexpected repaired ARMHF YSF literal reference")


def patch_binary(data: bytes) -> bytes:
    digest = sha256(data)
    if digest == PATCHED_SHA256:
        validate_repaired(data)
        return data
    require(digest == ORIGINAL_SHA256, f"unsupported ARMHF MMDVM_Bridge SHA256: {digest}")
    validate_original(data)

    candidate = bytearray(data)
    candidate[P25_ORIGINAL_OFFSET:P25_ORIGINAL_OFFSET + len(P25_ORIGINAL)] = P25_REPAIRED
    struct.pack_into("<I", candidate, LOAD_FILESZ_OFFSET, REPAIRED_SEGMENT_END)
    struct.pack_into("<I", candidate, LOAD_MEMSZ_OFFSET, REPAIRED_SEGMENT_END)
    candidate[PADDING_START:PADDING_END] = expected_padding()
    struct.pack_into("<I", candidate, YSF_REFERENCE_OFFSET, YSF_REPAIRED_ADDRESS)

    result = bytes(candidate)
    require(len(result) == len(data), "ARMHF binary size changed")
    validate_repaired(result)
    actual = sha256(result)
    require(actual == PATCHED_SHA256, f"internal ARMHF patched SHA256 mismatch: {actual}")
    return result


def patch_file(path: Path) -> None:
    original = path.read_bytes()
    repaired = patch_binary(original)
    if repaired != original:
        path.write_bytes(repaired)


def main() -> int:
    parser = argparse.ArgumentParser(description="Patch a temporary exact ARMHF MMDVM_Bridge build")
    parser.add_argument("--binary", required=True, type=Path)
    args = parser.parse_args()
    if not args.binary.is_file() or args.binary.is_symlink():
        parser.error("--binary must be a regular, non-symbolic-link file")
    try:
        patch_file(args.binary)
    except PatchError as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
