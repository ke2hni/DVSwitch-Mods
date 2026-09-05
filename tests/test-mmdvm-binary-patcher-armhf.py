#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Offline tests for the hash-specific ARMHF MMDVM_Bridge patcher."""

from __future__ import annotations

import hashlib
import importlib.util
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PATCHER = ROOT / "lib" / "patch_mmdvm_binary_armhf.py"
spec = importlib.util.spec_from_file_location("patch_mmdvm_binary_armhf", PATCHER)
assert spec and spec.loader
patcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patcher)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def make_original() -> bytes:
    data = bytearray(patcher.FILE_SIZE)
    data[:6] = b"\x7fELF\x01\x01"
    struct.pack_into("<H", data, 0x10, 2)
    struct.pack_into("<H", data, 0x12, 40)
    struct.pack_into("<I", data, 0x24, 0x05000400)
    struct.pack_into("<I", data, patcher.LOAD_FILESZ_OFFSET, patcher.ORIGINAL_SEGMENT_END)
    struct.pack_into("<I", data, patcher.LOAD_MEMSZ_OFFSET, patcher.ORIGINAL_SEGMENT_END)
    data[0x190:0x190 + len(patcher.BUILD_ID)] = patcher.BUILD_ID
    data[patcher.P25_ORIGINAL_OFFSET:patcher.P25_ORIGINAL_OFFSET + len(patcher.P25_ORIGINAL)] = patcher.P25_ORIGINAL
    data[patcher.YSF_ORIGINAL_OFFSET:patcher.YSF_ORIGINAL_OFFSET + len(patcher.YSF_ORIGINAL)] = patcher.YSF_ORIGINAL
    struct.pack_into("<I", data, patcher.YSF_REFERENCE_OFFSET, patcher.YSF_ORIGINAL_ADDRESS)
    return bytes(data)


def make_expected(original: bytes) -> bytes:
    data = bytearray(original)
    data[patcher.P25_ORIGINAL_OFFSET:patcher.P25_ORIGINAL_OFFSET + len(patcher.P25_ORIGINAL)] = patcher.P25_REPAIRED
    struct.pack_into("<I", data, patcher.LOAD_FILESZ_OFFSET, patcher.REPAIRED_SEGMENT_END)
    struct.pack_into("<I", data, patcher.LOAD_MEMSZ_OFFSET, patcher.REPAIRED_SEGMENT_END)
    data[patcher.PADDING_START:patcher.PADDING_END] = patcher.expected_padding()
    struct.pack_into("<I", data, patcher.YSF_REFERENCE_OFFSET, patcher.YSF_REPAIRED_ADDRESS)
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
    saved_repaired = patcher.PATCHED_SHA256
    try:
        patcher.ORIGINAL_SHA256 = hashlib.sha256(original).hexdigest()
        patcher.PATCHED_SHA256 = hashlib.sha256(expected).hexdigest()
        repaired = patcher.patch_binary(original)
        require(repaired == expected, "repair differs from independently constructed candidate")
        require(patcher.patch_binary(repaired) == repaired, "second repair was not idempotent")
        require(len(repaired) == len(original), "repair changed file size")

        damaged = bytearray(original)
        damaged[patcher.PADDING_START] = 1
        patcher.ORIGINAL_SHA256 = hashlib.sha256(damaged).hexdigest()
        expect_rejected(bytes(damaged), "padding")

        damaged = bytearray(original)
        struct.pack_into("<I", damaged, patcher.YSF_REFERENCE_OFFSET, 0)
        patcher.ORIGINAL_SHA256 = hashlib.sha256(damaged).hexdigest()
        expect_rejected(bytes(damaged), "literal reference")

        damaged = original[:-1]
        patcher.ORIGINAL_SHA256 = hashlib.sha256(damaged).hexdigest()
        expect_rejected(damaged, "file size")
    finally:
        patcher.ORIGINAL_SHA256 = saved_original
        patcher.PATCHED_SHA256 = saved_repaired

    print("PASS: hash-specific ARMHF MMDVM_Bridge binary patcher tests")


if __name__ == "__main__":
    main()
