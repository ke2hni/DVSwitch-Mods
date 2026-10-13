#!/usr/bin/env python3
"""Verify starter names merge into callsign-lookup.tsv without replacement."""
from __future__ import annotations
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MERGER = ROOT / "lib/merge_callsign_lookup.py"
STARTER = ROOT / "data/callsign-lookup.tsv"
STARTER_COUNT = len([line for line in STARTER.read_text().splitlines() if line.strip() and not line.lstrip().startswith("#")])


def run(operation: str, target: Path, starter: Path = STARTER) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(MERGER), operation, str(target), str(starter)],
        capture_output=True,
        text=True,
    )


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("FAIL: " + message)


with tempfile.TemporaryDirectory() as temporary:
    directory = Path(temporary)
    target = directory / "callsign-lookup.tsv"
    original = b"# personal entries\nMM0WTM = My saved name\nK1ABC\tUser entry"
    target.write_bytes(original)
    target.chmod(0o660)
    original_inode = target.stat().st_ino

    checked = run("--check", target)
    require(checked.returncode == 0 and checked.stdout.strip() == str(STARTER_COUNT - 1), "read-only check did not report the missing starter entries")
    require(target.read_bytes() == original and target.stat().st_ino == original_inode, "--check changed the user file")
    require(run("--is-sorted", target).stdout.strip() == "0", "unsorted existing callsigns were reported sorted")

    merged = run("--merge", target)
    require(merged.returncode == 0 and merged.stdout.strip() == str(STARTER_COUNT - 1), "merge did not append the missing starter entries")
    after = target.read_bytes()
    require(target.stat().st_ino == original_inode, "merge replaced the existing file")
    require(b"MM0WTM = My saved name\n" in after, "existing user value lost to a starter conflict")
    require(b"M0DMS = Daniel\n" in after, "new starter entry was not appended")
    require(b"K1ABC\tUser entry\n" in after, "existing tab-delimited row was not preserved")
    rows = [line for line in after.decode().splitlines() if line and not line.startswith("#")]
    callsigns = [line.split("=", 1)[0].split("\t", 1)[0].strip() for line in rows]
    require(callsigns == sorted(callsigns), "merged callsign entries are not alphabetically sorted")
    require(after.startswith(b"# personal entries\n"), "existing header comment was not preserved")
    require(run("--is-sorted", target).stdout.strip() == "1", "sorted callsign file was not detected")
    saved = target.read_bytes()
    repeated = run("--merge", target)
    require(repeated.returncode == 0 and repeated.stdout.strip() == "0", "repeat merge was not idempotent")
    require(target.read_bytes() == saved, "repeat merge changed the file")

with tempfile.TemporaryDirectory() as temporary:
    target = Path(temporary) / "new.tsv"
    checked = run("--check", target)
    require(checked.returncode == 0 and checked.stdout.strip() == str(STARTER_COUNT), "missing-file check did not report all starter rows")
    require(not target.exists(), "read-only check created a missing target")
    created = run("--merge", target)
    require(created.returncode == 0 and created.stdout.strip() == str(STARTER_COUNT), "merge did not initialize the missing file from starter rows")
    require(len(target.read_text().splitlines()) == STARTER_COUNT, "new file does not contain all starter rows")

with tempfile.TemporaryDirectory() as temporary:
    directory = Path(temporary)
    target = directory / "user.tsv"
    target.write_bytes(b"K1ABC = Keep this\n")
    bad_starter = directory / "bad-starter.tsv"
    bad_starter.write_text("K1ABC = Starter\nnot a valid row\n")
    before = target.read_bytes()
    result = run("--merge", target, bad_starter)
    require(result.returncode != 0, "malformed starter file was accepted")
    require(target.read_bytes() == before, "invalid starter data changed the user file")

print("PASS: callsign lookup starter merge preserves user data and is idempotent")
