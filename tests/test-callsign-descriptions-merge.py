#!/usr/bin/env python3
"""Verify starter description merges preserve user data and append safely."""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MERGER = ROOT / "lib/merge_callsign_descriptions.py"
STARTER = ROOT / "data/callsign-descriptions.tsv"


def run(operation: str, target: Path, starter: Path = STARTER) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["python3", str(MERGER), operation, str(target), str(starter)],
        text=True,
        capture_output=True,
        check=False,
    )


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    target = root / "callsign-descriptions.tsv"
    original = b"# user's comments stay\n9998 = My own announcement\nMY-LINK\tPrivate value"
    target.write_bytes(original)
    inode = target.stat().st_ino

    checked = run("--check", target)
    assert checked.returncode == 0 and checked.stdout.strip() == "10", checked
    assert target.read_bytes() == original and target.stat().st_ino == inode

    merged = run("--merge", target)
    assert merged.returncode == 0 and merged.stdout.strip() == "10", merged
    updated = target.read_bytes()
    assert target.stat().st_ino == inode, "merge replaced the user's file"
    assert updated.startswith(original + b"\n"), "merge changed existing bytes"
    assert b"9998 = My own announcement\n" in updated
    assert b"9998 = Announcement\n" not in updated, "conflicting user value was replaced"
    assert updated.count(b"AL-LINK = Alabama Link YSF Reflector Dashboard\n") == 1
    rerun = run("--merge", target)
    assert rerun.returncode == 0 and rerun.stdout.strip() == "0", rerun
    assert target.read_bytes() == updated

    absent = root / "new.tsv"
    created = run("--merge", absent)
    assert created.returncode == 0 and created.stdout.strip() == "11", created
    assert absent.read_text().count(" = ") == 11

    malformed = root / "malformed.tsv"
    malformed.write_text("GOOD = description\nBAD ENTRY\n")
    untouched = root / "untouched.tsv"
    untouched.write_bytes(b"MY-LINK = preserve\n")
    failure = run("--merge", untouched, malformed)
    assert failure.returncode == 1 and "invalid starter entry" in failure.stderr, failure
    assert untouched.read_bytes() == b"MY-LINK = preserve\n"

    symlink = root / "link.tsv"
    symlink.symlink_to(untouched)
    refusal = run("--merge", symlink)
    assert refusal.returncode == 1 and "symbolic-link" in refusal.stderr, refusal
    assert untouched.read_bytes() == b"MY-LINK = preserve\n"

print("PASS: callsign description starter merges preserve existing data, append only missing rows, and are idempotent")
