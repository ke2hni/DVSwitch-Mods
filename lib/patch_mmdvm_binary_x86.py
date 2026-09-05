#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

"""Apply hash-specific, fixed-size AMD64/i386 MMDVM_Bridge repairs.

No upstream executable is distributed.  The corrected format strings are
placed in verified file padding, the existing executable PT_LOAD segment is
extended to map them, and every known RIP-relative reference is redirected.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path


class PatchError(RuntimeError):
    pass


ORIGINAL_SHA256 = "afc4c7f30ac3376afb195b71facfab102fcda5c7b3d0b5e03e42cfad69e7b380"
PATCHED_SHA256 = "9c408f4395859bb1059f5e19e292551fe98f13e1e87c0e1eb4983a4cca3d124f"
FILE_SIZE = 5_428_248
BUILD_ID = bytes.fromhex("9751eacc365f9986a9f6a0c62eac7d0709f8c2ae")

PADDING_START = 0xAA430
PADDING_END = 0xAA540
NEW_SEGMENT_END = 0xAA470
P25_ADDRESS = 0xAA430
YSF_ADDRESS = 0xAA450
YSF_REFERENCE_OFFSET = 0x73BB3
YSF_ORIGINAL_ADDRESS = 0x98D99

P25_ORIGINAL = b"REMOTE@%s:%d!TalkGroup%d\0"
YSF_ORIGINAL = b"REMOTE@%s:%d!Link%c%c%c%05d\0"
P25_RELOCATED = b"REMOTE@%s:%d!TalkGroup %d\0"
YSF_RELOCATED = b"REMOTE@%s:%d!Link%c%c%c %05d\0"

# Offset of each seven-byte `lea disp32(%rip), %rsi`, followed by its target.
REFERENCES = (
    (0x59543, 0x925B1, P25_ADDRESS),
    (0x4487D, 0x925B1, P25_ADDRESS),
)

# ELF64 program-header fields for the first PT_LOAD (program header index 2).
LOAD_FILESZ_OFFSET = 0xD0
LOAD_MEMSZ_OFFSET = 0xD8
ORIGINAL_SEGMENT_END = 0xAA430

I386_ORIGINAL_SHA256 = "40d2a2b98d928441b5f5c118fee164147d509f6272d855f25f84f586ee08e1c5"
I386_PATCHED_SHA256 = "440afcbd69c7a0ebe5414a957dda5a8299ba90ec0d10df09a70e7bcade136103"
I386_FILE_SIZE = 4_491_752
I386_BUILD_ID = bytes.fromhex("23f9406751544d3b674357ba6b5d48f66c7b7969")
I386_PADDING_START = 0xBB651
I386_PADDING_END = 0xBBA98
I386_NEW_SEGMENT_END = 0xBB6A0
I386_P25_ADDRESS = 0xBB660
I386_YSF_ADDRESS = 0xBB680
I386_GOT_BASE = 0xBD000
I386_P25_ORIGINAL_ADDRESS = 0x99DD1
I386_YSF_ORIGINAL_ADDRESS = 0xA04CB
I386_P25_REFERENCES = (0x5F41A, 0x48EA0)
I386_YSF_REFERENCE = 0x7B59F
# ELF32 program header index 2: p_filesz and p_memsz.
I386_LOAD_FILESZ_OFFSET = 0x84
I386_LOAD_MEMSZ_OFFSET = 0x88
I386_ORIGINAL_SEGMENT_END = 0xBB651


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PatchError(message)


def count(data: bytes, value: bytes, description: str, expected: int) -> None:
    actual = data.count(value)
    require(actual == expected, f"unexpected {description} count: {actual} (expected {expected})")


def lea_bytes(instruction_offset: int, target: int) -> bytes:
    displacement = target - (instruction_offset + 7)
    return b"\x48\x8d\x35" + struct.pack("<i", displacement)


def expected_padding() -> bytes:
    padding = bytearray(PADDING_END - PADDING_START)
    p25 = P25_ADDRESS - PADDING_START
    ysf = YSF_ADDRESS - PADDING_START
    padding[p25:p25 + len(P25_RELOCATED)] = P25_RELOCATED
    padding[ysf:ysf + len(YSF_RELOCATED)] = YSF_RELOCATED
    return bytes(padding)


def i386_lea_bytes(target: int) -> bytes:
    return b"\x8d\x83" + struct.pack("<i", target - I386_GOT_BASE)


def i386_expected_padding() -> bytes:
    padding = bytearray(I386_PADDING_END - I386_PADDING_START)
    p25 = I386_P25_ADDRESS - I386_PADDING_START
    ysf = I386_YSF_ADDRESS - I386_PADDING_START
    padding[p25:p25 + len(P25_RELOCATED)] = P25_RELOCATED
    padding[ysf:ysf + len(YSF_RELOCATED)] = YSF_RELOCATED
    return bytes(padding)


def validate_i386_common(data: bytes) -> None:
    require(len(data) == I386_FILE_SIZE, f"unsupported i386 file size: {len(data)}")
    require(data[:6] == b"\x7fELF\x01\x01", "not a little-endian ELF32 executable")
    require(struct.unpack_from("<H", data, 0x10)[0] == 3, "unsupported i386 ELF type")
    require(struct.unpack_from("<H", data, 0x12)[0] == 3, "unsupported ELF machine (expected i386)")
    require(data.count(I386_BUILD_ID) == 1, "missing or ambiguous expected i386 GNU build ID")
    count(data, P25_ORIGINAL, "original i386 P25 format string", 1)
    count(data, YSF_ORIGINAL, "original i386 YSF format string", 1)


def validate_i386_original(data: bytes) -> None:
    validate_i386_common(data)
    require(struct.unpack_from("<I", data, I386_LOAD_FILESZ_OFFSET)[0] == I386_ORIGINAL_SEGMENT_END,
            "unexpected original i386 executable-segment file size")
    require(struct.unpack_from("<I", data, I386_LOAD_MEMSZ_OFFSET)[0] == I386_ORIGINAL_SEGMENT_END,
            "unexpected original i386 executable-segment memory size")
    require(data[I386_PADDING_START:I386_PADDING_END] == bytes(I386_PADDING_END - I386_PADDING_START),
            "i386 relocation padding is not entirely zero-filled")
    for offset in I386_P25_REFERENCES:
        require(data[offset:offset + 6] == i386_lea_bytes(I386_P25_ORIGINAL_ADDRESS),
                f"unexpected original i386 P25 reference at 0x{offset:x}")
    require(data[I386_YSF_REFERENCE:I386_YSF_REFERENCE + 6] == i386_lea_bytes(I386_YSF_ORIGINAL_ADDRESS),
            "unexpected original i386 YSF reference")


def validate_i386_patched(data: bytes) -> None:
    validate_i386_common(data)
    require(struct.unpack_from("<I", data, I386_LOAD_FILESZ_OFFSET)[0] == I386_NEW_SEGMENT_END,
            "unexpected patched i386 executable-segment file size")
    require(struct.unpack_from("<I", data, I386_LOAD_MEMSZ_OFFSET)[0] == I386_NEW_SEGMENT_END,
            "unexpected patched i386 executable-segment memory size")
    require(data[I386_PADDING_START:I386_PADDING_END] == i386_expected_padding(),
            "relocated i386 strings or unused padding are invalid")
    for offset in I386_P25_REFERENCES:
        require(data[offset:offset + 6] == i386_lea_bytes(I386_P25_ADDRESS),
                f"unexpected patched i386 P25 reference at 0x{offset:x}")
    require(data[I386_YSF_REFERENCE:I386_YSF_REFERENCE + 6] == i386_lea_bytes(I386_YSF_ADDRESS),
            "unexpected patched i386 YSF reference")


def patch_i386(data: bytes) -> bytes:
    digest = sha256(data)
    if digest == I386_PATCHED_SHA256:
        validate_i386_patched(data)
        return data
    require(digest == I386_ORIGINAL_SHA256, f"unsupported i386 MMDVM_Bridge SHA256: {digest}")
    validate_i386_original(data)
    candidate = bytearray(data)
    struct.pack_into("<I", candidate, I386_LOAD_FILESZ_OFFSET, I386_NEW_SEGMENT_END)
    struct.pack_into("<I", candidate, I386_LOAD_MEMSZ_OFFSET, I386_NEW_SEGMENT_END)
    candidate[I386_PADDING_START:I386_PADDING_END] = i386_expected_padding()
    for offset in I386_P25_REFERENCES:
        candidate[offset:offset + 6] = i386_lea_bytes(I386_P25_ADDRESS)
    candidate[I386_YSF_REFERENCE:I386_YSF_REFERENCE + 6] = i386_lea_bytes(I386_YSF_ADDRESS)
    result = bytes(candidate)
    require(len(result) == len(data), "i386 binary size changed")
    validate_i386_patched(result)
    actual = sha256(result)
    require(I386_PATCHED_SHA256 != "TO_BE_FILLED",
            f"internal i386 patched SHA256 is not configured; calculated {actual}")
    require(actual == I386_PATCHED_SHA256, f"internal i386 patched SHA256 mismatch: {actual}")
    return result


def validate_common(data: bytes) -> None:
    require(len(data) == FILE_SIZE, f"unsupported file size: {len(data)}")
    require(data[:4] == b"\x7fELF", "not an ELF executable")
    require(data[4] == 2, "unsupported ELF class (expected ELF64)")
    require(data[5] == 1, "unsupported ELF byte order (expected little-endian)")
    require(struct.unpack_from("<H", data, 0x10)[0] == 3, "unsupported ELF type (expected PIE)")
    require(struct.unpack_from("<H", data, 0x12)[0] == 62, "unsupported ELF machine (expected x86-64)")
    require(data.count(BUILD_ID) == 1, "missing or ambiguous expected GNU build ID")
    count(data, P25_ORIGINAL, "original P25 format string", 1)
    count(data, YSF_ORIGINAL, "original YSF format string", 1)


def validate_original(data: bytes) -> None:
    validate_common(data)
    require(struct.unpack_from("<Q", data, LOAD_FILESZ_OFFSET)[0] == ORIGINAL_SEGMENT_END,
            "unexpected original executable-segment file size")
    require(struct.unpack_from("<Q", data, LOAD_MEMSZ_OFFSET)[0] == ORIGINAL_SEGMENT_END,
            "unexpected original executable-segment memory size")
    require(data[PADDING_START:PADDING_END] == bytes(PADDING_END - PADDING_START),
            "relocation padding is not entirely zero-filled")
    for offset, old_target, _new_target in REFERENCES:
        require(data[offset:offset + 7] == lea_bytes(offset, old_target),
                f"unexpected original reference instruction at 0x{offset:x}")
    require(data[YSF_REFERENCE_OFFSET:YSF_REFERENCE_OFFSET + 7] ==
            lea_bytes(YSF_REFERENCE_OFFSET, YSF_ORIGINAL_ADDRESS),
            "unexpected original YSF reference instruction")


def validate_patched(data: bytes) -> None:
    validate_common(data)
    require(struct.unpack_from("<Q", data, LOAD_FILESZ_OFFSET)[0] == NEW_SEGMENT_END,
            "unexpected patched executable-segment file size")
    require(struct.unpack_from("<Q", data, LOAD_MEMSZ_OFFSET)[0] == NEW_SEGMENT_END,
            "unexpected patched executable-segment memory size")
    require(data[PADDING_START:PADDING_END] == expected_padding(),
            "relocated strings, YSF selector, or unused padding are invalid")
    for offset, _old_target, new_target in REFERENCES:
        require(data[offset:offset + 7] == lea_bytes(offset, new_target),
                f"unexpected patched reference instruction at 0x{offset:x}")
    require(data[YSF_REFERENCE_OFFSET:YSF_REFERENCE_OFFSET + 7] ==
            lea_bytes(YSF_REFERENCE_OFFSET, YSF_ADDRESS),
            "unexpected patched YSF reference instruction")


def patch_binary(data: bytes) -> bytes:
    digest = sha256(data)
    if digest in (I386_ORIGINAL_SHA256, I386_PATCHED_SHA256):
        return patch_i386(data)
    if digest == PATCHED_SHA256:
        validate_patched(data)
        return data
    if digest != ORIGINAL_SHA256:
        raise PatchError(f"unsupported AMD64/i386 MMDVM_Bridge SHA256: {digest}")

    validate_original(data)
    candidate = bytearray(data)
    struct.pack_into("<Q", candidate, LOAD_FILESZ_OFFSET, NEW_SEGMENT_END)
    struct.pack_into("<Q", candidate, LOAD_MEMSZ_OFFSET, NEW_SEGMENT_END)
    candidate[PADDING_START:PADDING_END] = expected_padding()
    for offset, _old_target, new_target in REFERENCES:
        candidate[offset:offset + 7] = lea_bytes(offset, new_target)
    candidate[YSF_REFERENCE_OFFSET:YSF_REFERENCE_OFFSET + 7] = \
        lea_bytes(YSF_REFERENCE_OFFSET, YSF_ADDRESS)

    result = bytes(candidate)
    require(len(result) == len(data), "binary size changed")
    validate_patched(result)
    expected = PATCHED_SHA256
    actual = sha256(result)
    require(expected != "TO_BE_FILLED", f"internal patched SHA256 is not configured; calculated {actual}")
    require(actual == expected, f"internal patched SHA256 mismatch: {actual}")
    return result


def patch_file(path: Path) -> None:
    original = path.read_bytes()
    patched = patch_binary(original)
    if patched != original:
        path.write_bytes(patched)


def main() -> int:
    parser = argparse.ArgumentParser(description="Patch a temporary AMD64/i386 MMDVM_Bridge copy")
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
