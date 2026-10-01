#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Record DVSwitch mode transitions for timestamp-accurate activity labels."""

from __future__ import annotations

import fcntl
import os
from pathlib import Path
import tempfile

STATE_FILE = Path(os.environ.get("DVS_ACTIVITY_MODE_STATE", "/var/lib/dvswitch-mode-buttons/current-mode"))
LAST_DMR_FILE = Path(os.environ.get("DVS_ACTIVITY_LAST_DMR", "/var/lib/dvswitch-mode-buttons/last-dmr-network"))
HISTORY_FILE = Path(os.environ.get("DVS_ACTIVITY_MODE_HISTORY", "/var/lib/dvswitch-mods/activity-mode-history.tsv"))
LOCK_FILE = Path(os.environ.get("DVS_ACTIVITY_MODE_LOCK", "/run/lock/dvswitch-mods-activity-mode-history.lock"))
ALLOWED_MODES = {"BM", "TGIF", "STFU", "YSF", "P25", "NXDN", "DSTAR"}
MAX_HISTORY_ROWS = 8192


def read_state(path: Path) -> tuple[int, str] | None:
    try:
        mode = path.read_text(encoding="utf-8").strip().upper()
        stamp = int(path.stat().st_mtime)
    except (OSError, UnicodeError, ValueError):
        return None
    return (stamp, mode) if mode in ALLOWED_MODES else None


def read_history(path: Path) -> list[tuple[int, str]]:
    try:
        lines = path.read_text(encoding="ascii").splitlines()
    except FileNotFoundError:
        return []
    except (OSError, UnicodeError):
        return []
    rows: list[tuple[int, str]] = []
    for line in lines:
        parts = line.split("\t", 1)
        if len(parts) != 2 or not parts[0].isdigit() or parts[1] not in ALLOWED_MODES:
            continue
        rows.append((int(parts[0]), parts[1]))
    return rows


def write_history(path: Path, rows: list[tuple[int, str]]) -> None:
    path.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".activity-mode-history.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="ascii", newline="\n") as stream:
            for stamp, mode in rows[-MAX_HISTORY_ROWS:]:
                stream.write(f"{stamp}\t{mode}\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, 0o644)
        os.replace(name, path)
    finally:
        try:
            os.unlink(name)
        except FileNotFoundError:
            pass


def append_transition(rows: list[tuple[int, str]], transition: tuple[int, str] | None) -> None:
    if transition is None:
        return
    if rows and rows[-1] == transition:
        return
    rows.append(transition)


def main() -> None:
    LOCK_FILE.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    with LOCK_FILE.open("a", encoding="ascii") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        rows = read_history(HISTORY_FILE)

        # The Buttons repository preserves the most recently selected DMR
        # network separately. Seed it before current mode on first install so
        # recent DMR rows remain attributable across a later YSF/P25 switch.
        if not rows:
            seed = read_state(LAST_DMR_FILE)
            if seed is not None and seed[1] in {"BM", "TGIF"}:
                append_transition(rows, seed)

        append_transition(rows, read_state(STATE_FILE))
        if rows:
            write_history(HISTORY_FILE, rows)


if __name__ == "__main__":
    main()
