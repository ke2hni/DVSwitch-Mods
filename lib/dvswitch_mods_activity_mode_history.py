#!/usr/bin/env python3
# Version: 1.0.0
# SPDX-License-Identifier: MIT

"""Record DVSwitch mode transitions for timestamp-accurate activity labels."""

from __future__ import annotations

import fcntl
import glob
import json
import os
from pathlib import Path
import tempfile
import time

STATE_FILE = Path(os.environ.get("DVS_ACTIVITY_MODE_STATE", "/var/lib/dvswitch-mode-buttons/current-mode"))
LAST_DMR_FILE = Path(os.environ.get("DVS_ACTIVITY_LAST_DMR", "/var/lib/dvswitch-mode-buttons/last-dmr-network"))
HISTORY_FILE = Path(os.environ.get("DVS_ACTIVITY_MODE_HISTORY", "/var/lib/dvswitch-mods/activity-mode-history.tsv"))
LOCK_FILE = Path(os.environ.get("DVS_ACTIVITY_MODE_LOCK", "/run/lock/dvswitch-mods-activity-mode-history.lock"))
ABINFO_GLOB = os.environ.get("DVS_ACTIVITY_ABINFO_GLOB", "/tmp/ABInfo_*.json")
BRIDGE_INI = Path(os.environ.get("DVS_ACTIVITY_BRIDGE_INI", "/opt/MMDVM_Bridge/MMDVM_Bridge.ini"))
ALLOWED_MODES = {"BM", "TGIF", "STFU", "YSF", "P25", "NXDN", "DSTAR"}
MAX_HISTORY_ROWS = 8192


def read_state(path: Path) -> tuple[float, str] | None:
    try:
        mode = path.read_text(encoding="utf-8").strip().upper()
        stamp = path.stat().st_mtime
    except (OSError, UnicodeError, ValueError):
        return None
    return (stamp, mode) if mode in ALLOWED_MODES else None


def read_dmr_network() -> str | None:
    try:
        in_network = False
        for line in BRIDGE_INI.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped == "[DMR Network]":
                in_network = True
                continue
            if in_network and stripped.startswith("["):
                break
            if in_network and stripped.lower().startswith("address") and "=" in stripped:
                address = stripped.split("=", 1)[1].strip().lower()
                if "tgif" in address:
                    return "TGIF"
                if "brandmeister" in address or "repeater.net" in address:
                    return "BM"
                break
    except (OSError, UnicodeError):
        pass
    fallback = read_state(LAST_DMR_FILE)
    return fallback[1] if fallback is not None and fallback[1] in {"BM", "TGIF"} else None


def read_live_mode() -> tuple[float, str] | None:
    """Mirror the Buttons dashboard status API from fresh Analog_Bridge state."""
    files = glob.glob(ABINFO_GLOB)
    if not files:
        return None
    path = max((Path(name) for name in files), key=lambda item: item.stat().st_mtime)
    try:
        stamp = path.stat().st_mtime
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    tlv = data.get("tlv")
    values = [tlv.get("ambe_mode", "") if isinstance(tlv, dict) else "", data.get("ambe_mode", "")]
    live_mode = ""
    for value in values:
        value = str(value).strip().upper()
        if value in {"YSFN", "YSFW"}:
            value = "YSF"
        if value in {"DMR", "STFU", "YSF", "P25", "NXDN", "DSTAR"}:
            live_mode = value
            break
    if not live_mode:
        return None
    if live_mode == "DMR":
        network = read_dmr_network()
        if network is None:
            return None
        live_mode = network
    return stamp, live_mode


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
    normalized = (int(transition[0]), transition[1])
    if rows and rows[-1][1] == normalized[1]:
        return
    rows.append(normalized)


def main() -> None:
    LOCK_FILE.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    with LOCK_FILE.open("a", encoding="ascii") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        rows = read_history(HISTORY_FILE)

        state = read_state(STATE_FILE)
        live = read_live_mode()

        # At boot the dashboard status API derives its selected mode from
        # fresh ABInfo plus the live DMR address, while current-mode can still
        # contain the mode selected before shutdown. Record the live mode as a
        # new transition only when ABInfo is newer than that saved state.
        if live is not None and (state is None or live[0] >= state[0]):
            append_transition(rows, (int(time.time()), live[1]))

        # Preserve the most recently selected DMR network as a first-install
        # seed when no live ABInfo is available yet.
        if not rows:
            seed = read_state(LAST_DMR_FILE)
            if seed is not None and seed[1] in {"BM", "TGIF"}:
                append_transition(rows, seed)

        # The saved state remains the best source during the brief interval
        # before a fresh ABInfo file reflects a just-selected mode.
        if live is None or state is None or live[0] < state[0]:
            append_transition(rows, state)
        # Create the history file even when neither a saved selection nor live
        # ABInfo is available yet. This keeps installation independent of the
        # optional Mode Buttons component and lets later bridge-config events
        # populate the file as soon as runtime state becomes available.
        write_history(HISTORY_FILE, rows)


if __name__ == "__main__":
    main()
