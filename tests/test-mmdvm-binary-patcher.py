#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

"""Regression tests for architecture-aware MMDVM_Bridge binary repairs."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parents[1]
PATCHER = ROOT / "lib" / "patch_mmdvm_binary.py"
SPEC = importlib.util.spec_from_file_location("patch_mmdvm_binary", PATCHER)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def elf(machine: int, body: bytes) -> bytes:
    header = bytearray(64)
    header[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<H", header, 18, machine)
    return bytes(header) + body


def verify(machine: int, p25_old: bytes, p25_new: bytes, ysf_old: bytes, ysf_new: bytes) -> None:
    original = elf(machine, b"prefix" + p25_old + b"middle" + ysf_old + b"suffix")
    repaired = MODULE.patch_binary(original)
    assert len(repaired) == len(original)
    assert repaired.count(p25_old) == (1 if p25_old == p25_new else 0)
    assert repaired.count(p25_new) == 1
    assert repaired.count(ysf_old) == 0
    assert repaired.count(ysf_new) == 1
    assert MODULE.patch_binary(repaired) == repaired


verify(183, MODULE.P25_PADDED_OLD, MODULE.P25_PADDED_NEW,
       MODULE.YSF_PADDED_OLD, MODULE.YSF_PADDED_NEW)
verify(40, MODULE.P25_PADDED_OLD, MODULE.P25_PADDED_NEW,
       MODULE.YSF_TIGHT_OLD, MODULE.YSF_TIGHT_NEW)
verify(62, MODULE.P25_TIGHT_OLD, MODULE.P25_TIGHT_OLD,
       MODULE.YSF_TIGHT_OLD, MODULE.YSF_TIGHT_NEW)
verify(3, MODULE.P25_TIGHT_OLD, MODULE.P25_TIGHT_OLD,
       MODULE.YSF_TIGHT_OLD, MODULE.YSF_TIGHT_NEW)

try:
    MODULE.patch_binary(elf(999, MODULE.P25_TIGHT_OLD + MODULE.YSF_TIGHT_OLD))
except MODULE.PatchError:
    pass
else:
    raise AssertionError("unsupported ELF machine was accepted")

print("PASS: architecture-aware MMDVM_Bridge binary patcher tests")
