#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Offline tests for the separate hash-specific x86 MMDVM patcher."""

from __future__ import annotations

import hashlib
import importlib.util
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PATCHER = ROOT / "lib" / "patch_mmdvm_binary_x86.py"
spec = importlib.util.spec_from_file_location("patch_mmdvm_binary_x86", PATCHER)
assert spec and spec.loader
patcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patcher)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def make_original() -> bytes:
    data = bytearray(patcher.FILE_SIZE)
    data[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<H", data, 0x10, 3)
    struct.pack_into("<H", data, 0x12, 62)
    struct.pack_into("<Q", data, patcher.LOAD_FILESZ_OFFSET, patcher.ORIGINAL_SEGMENT_END)
    struct.pack_into("<Q", data, patcher.LOAD_MEMSZ_OFFSET, patcher.ORIGINAL_SEGMENT_END)
    data[0x274:0x274 + len(patcher.BUILD_ID)] = patcher.BUILD_ID
    data[0x925B1:0x925B1 + len(patcher.P25_ORIGINAL)] = patcher.P25_ORIGINAL
    data[0x98D99:0x98D99 + len(patcher.YSF_ORIGINAL)] = patcher.YSF_ORIGINAL
    for offset, old_target, _new_target in patcher.REFERENCES:
        data[offset:offset + 7] = patcher.lea_bytes(offset, old_target)
    data[patcher.YSF_REFERENCE_OFFSET:patcher.YSF_REFERENCE_OFFSET + 7] = \
        patcher.lea_bytes(patcher.YSF_REFERENCE_OFFSET, patcher.YSF_ORIGINAL_ADDRESS)
    return bytes(data)


def make_expected(original: bytes) -> bytes:
    data = bytearray(original)
    struct.pack_into("<Q", data, patcher.LOAD_FILESZ_OFFSET, patcher.NEW_SEGMENT_END)
    struct.pack_into("<Q", data, patcher.LOAD_MEMSZ_OFFSET, patcher.NEW_SEGMENT_END)
    data[patcher.PADDING_START:patcher.PADDING_END] = patcher.expected_padding()
    for offset, _old_target, new_target in patcher.REFERENCES:
        data[offset:offset + 7] = patcher.lea_bytes(offset, new_target)
    data[patcher.YSF_REFERENCE_OFFSET:patcher.YSF_REFERENCE_OFFSET + 7] = \
        patcher.lea_bytes(patcher.YSF_REFERENCE_OFFSET, patcher.YSF_ADDRESS)
    return bytes(data)


def make_i386_original() -> bytes:
    data = bytearray(patcher.I386_FILE_SIZE)
    data[:6] = b"\x7fELF\x01\x01"
    struct.pack_into("<H", data, 0x10, 3)
    struct.pack_into("<H", data, 0x12, 3)
    struct.pack_into("<I", data, patcher.I386_LOAD_FILESZ_OFFSET, patcher.I386_ORIGINAL_SEGMENT_END)
    struct.pack_into("<I", data, patcher.I386_LOAD_MEMSZ_OFFSET, patcher.I386_ORIGINAL_SEGMENT_END)
    data[0x188:0x188 + len(patcher.I386_BUILD_ID)] = patcher.I386_BUILD_ID
    data[patcher.I386_P25_ORIGINAL_ADDRESS:patcher.I386_P25_ORIGINAL_ADDRESS + len(patcher.P25_ORIGINAL)] = patcher.P25_ORIGINAL
    data[patcher.I386_YSF_ORIGINAL_ADDRESS:patcher.I386_YSF_ORIGINAL_ADDRESS + len(patcher.YSF_ORIGINAL)] = patcher.YSF_ORIGINAL
    for offset in patcher.I386_P25_REFERENCES:
        data[offset:offset + 6] = patcher.i386_lea_bytes(patcher.I386_P25_ORIGINAL_ADDRESS)
    data[patcher.I386_YSF_REFERENCE:patcher.I386_YSF_REFERENCE + 6] = \
        patcher.i386_lea_bytes(patcher.I386_YSF_ORIGINAL_ADDRESS)
    return bytes(data)


def make_i386_expected(original: bytes) -> bytes:
    data = bytearray(original)
    struct.pack_into("<I", data, patcher.I386_LOAD_FILESZ_OFFSET, patcher.I386_NEW_SEGMENT_END)
    struct.pack_into("<I", data, patcher.I386_LOAD_MEMSZ_OFFSET, patcher.I386_NEW_SEGMENT_END)
    data[patcher.I386_PADDING_START:patcher.I386_PADDING_END] = patcher.i386_expected_padding()
    for offset in patcher.I386_P25_REFERENCES:
        data[offset:offset + 6] = patcher.i386_lea_bytes(patcher.I386_P25_ADDRESS)
    data[patcher.I386_YSF_REFERENCE:patcher.I386_YSF_REFERENCE + 6] = \
        patcher.i386_lea_bytes(patcher.I386_YSF_ADDRESS)
    return bytes(data)


def expect_rejected(data: bytes, phrase: str) -> None:
    try:
        patcher.patch_binary(data)
    except patcher.PatchError as exc:
        require(phrase in str(exc), f"wrong rejection for {phrase!r}: {exc}")
    else:
        raise AssertionError(f"accepted invalid state: {phrase}")


def main() -> None:
    original = make_original()
    expected = make_expected(original)
    saved_original = patcher.ORIGINAL_SHA256
    saved_patched = patcher.PATCHED_SHA256
    try:
        patcher.ORIGINAL_SHA256 = hashlib.sha256(original).hexdigest()
        patcher.PATCHED_SHA256 = hashlib.sha256(expected).hexdigest()
        repaired = patcher.patch_binary(original)
        require(repaired == expected, "repair differs from independently constructed candidate")
        require(patcher.patch_binary(repaired) == repaired, "second patch was not idempotent")
        require(len(repaired) == len(original), "repair changed file size")

        damaged = bytearray(original)
        damaged[patcher.PADDING_START] = 1
        patcher.ORIGINAL_SHA256 = hashlib.sha256(damaged).hexdigest()
        expect_rejected(bytes(damaged), "padding")

        damaged = bytearray(original)
        damaged[patcher.REFERENCES[0][0]] ^= 1
        patcher.ORIGINAL_SHA256 = hashlib.sha256(damaged).hexdigest()
        expect_rejected(bytes(damaged), "reference instruction")

        damaged = original[:-1]
        patcher.ORIGINAL_SHA256 = hashlib.sha256(damaged).hexdigest()
        expect_rejected(damaged, "file size")
    finally:
        patcher.ORIGINAL_SHA256 = saved_original
        patcher.PATCHED_SHA256 = saved_patched

    i386_original = make_i386_original()
    i386_expected = make_i386_expected(i386_original)
    saved_i386_original = patcher.I386_ORIGINAL_SHA256
    saved_i386_patched = patcher.I386_PATCHED_SHA256
    try:
        patcher.I386_ORIGINAL_SHA256 = hashlib.sha256(i386_original).hexdigest()
        patcher.I386_PATCHED_SHA256 = hashlib.sha256(i386_expected).hexdigest()
        repaired = patcher.patch_binary(i386_original)
        require(repaired == i386_expected, "i386 repair differs from expected candidate")
        require(patcher.patch_binary(repaired) == repaired, "second i386 patch was not idempotent")
        require(len(repaired) == len(i386_original), "i386 repair changed file size")

        damaged = bytearray(i386_original)
        damaged[patcher.I386_P25_REFERENCES[0]] ^= 1
        patcher.I386_ORIGINAL_SHA256 = hashlib.sha256(damaged).hexdigest()
        expect_rejected(bytes(damaged), "i386 P25 reference")
    finally:
        patcher.I386_ORIGINAL_SHA256 = saved_i386_original
        patcher.I386_PATCHED_SHA256 = saved_i386_patched

    print("PASS: hash-specific AMD64/i386 MMDVM_Bridge binary patcher tests")


if __name__ == "__main__":
    main()
