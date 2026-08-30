#!/usr/bin/env python3

import importlib.util
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "lib" / "patch_mmdvm_binary.py"
spec = importlib.util.spec_from_file_location("patch_mmdvm_binary", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


p25_old = b"REMOTE@%s:%d!TalkGroup%d\x00\x00"
p25_new = b"REMOTE@%s:%d!TalkGroup %d\x00"
ysf_old = b"REMOTE@%s:%d!Link%c%c%c%05d\x00\x00"
ysf_new = b"REMOTE@%s:%d!Link%c%c%c %05d\x00"
fixture = b"ELF-fixture\x00" + p25_old + b"middle\x00" + ysf_old + b"end"

patched = module.patch_binary(fixture)
require(len(patched) == len(fixture), "patch changed binary size")
require(patched.count(p25_new) == 1 and p25_old not in patched, "P25 spacing patch failed")
require(patched.count(ysf_new) == 1 and ysf_old not in patched, "YSF spacing patch failed")
require(module.patch_binary(patched) == patched, "binary patch is not idempotent")

mixed = b"prefix" + p25_new + b"middle" + ysf_old + b"suffix"
mixed_patched = module.patch_binary(mixed)
require(mixed_patched.count(p25_new) == 1, "existing P25 patch was not preserved")
require(mixed_patched.count(ysf_new) == 1, "missing YSF patch was not applied")

for bad in (
    b"no supported patterns",
    p25_old + p25_old + ysf_old,
    p25_old + ysf_old + ysf_new,
):
    try:
        module.patch_binary(bad)
    except module.PatchError:
        pass
    else:
        raise AssertionError("ambiguous or unsupported binary was accepted")

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "MMDVM_Bridge"
    path.write_bytes(fixture)
    module.patch_file(path)
    require(path.read_bytes() == patched, "file patch result is incorrect")

print("MMDVM binary patcher tests passed.")
