#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Record timestamped BM/TGIF selections for Gateway Activity labels."""

from __future__ import annotations

import argparse
import fcntl
import os
from pathlib import Path
import tempfile
import time

HISTORY_FILE = Path(os.environ.get(
    "DVS_DMR_NETWORK_HISTORY_FILE", "/var/lib/dvswitch-mods/dmr-network-history.tsv"
))
LOCK_FILE = Path(os.environ.get(
    "DVS_DMR_NETWORK_HISTORY_LOCK", "/run/lock/dvswitch-mods-dmr-network-history.lock"
))
BRIDGE_INI = Path(os.environ.get(
    "DVS_MMDVM_BRIDGE_INI", "/opt/MMDVM_Bridge/MMDVM_Bridge.ini"
))
NETWORKS = {"BM", "TGIF"}


def read_history(path: Path) -> list[tuple[int, str]]:
    try:
        lines = path.read_text(encoding="ascii").splitlines()
    except (OSError, UnicodeError):
        return []
    rows: list[tuple[int, str]] = []
    for line in lines:
        fields = line.split("\t", 1)
        if len(fields) == 2 and fields[0].isdigit() and fields[1] in NETWORKS:
            rows.append((int(fields[0]), fields[1]))
    return rows


def network_from_ini(path: Path) -> str | None:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError):
        return None
    in_dmr = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("["):
            in_dmr = stripped == "[DMR Network]"
            continue
        if in_dmr and stripped.lower().startswith("address") and "=" in stripped:
            address = stripped.split("=", 1)[1].strip().lower()
            if "tgif" in address:
                return "TGIF"
            if "brandmeister" in address or "repeater.net" in address or "3102" in address or "3104" in address:
                return "BM"
            return None
    return None


def write_history(path: Path, rows: list[tuple[int, str]]) -> None:
    path.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o755)
    fd, temporary = tempfile.mkstemp(prefix=".dmr-network-history.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="ascii", newline="\n") as stream:
            previous_mode = None
            for stamp, network in sorted(rows, key=lambda row: row[0]):
                if previous_mode == network:
                    continue
                stream.write(f"{stamp}\t{network}\n")
                previous_mode = network
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def record(network: str, timestamp_ms: int) -> bool:
    network = network.upper()
    if network not in NETWORKS:
        raise ValueError("network must be BM or TGIF")
    if timestamp_ms < 0:
        raise ValueError("timestamp must be a nonnegative epoch-millisecond value")

    LOCK_FILE.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    with LOCK_FILE.open("a", encoding="ascii") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        rows = read_history(HISTORY_FILE)
        # A watcher may observe the replaced INI a fraction after the button
        # hook records the same choice. Treat identical timestamps as one event.
        if any(stamp == timestamp_ms and value == network for stamp, value in rows):
            return False
        prior = [(stamp, index, value) for index, (stamp, value) in enumerate(rows) if stamp <= timestamp_ms]
        if prior and max(prior)[2] == network:
            return False
        rows.append((timestamp_ms, network))
        # Collapse adjacent repeats after sorting, including a watcher event
        # that raced the button hook and was timestamped a few ms later.
        rows = sorted(rows, key=lambda row: row[0])
        compacted: list[tuple[int, str]] = []
        for row in rows:
            if compacted and compacted[-1][1] == row[1]:
                continue
            compacted.append(row)
        write_history(HISTORY_FILE, compacted)
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--record", nargs=2, metavar=("BM|TGIF", "EPOCH_MS"))
    action.add_argument("--current", action="store_true", help="record the current bridge network at INI modification time")
    action.add_argument("--seed-current", action="store_true", help="seed the current bridge network from installation time")
    args = parser.parse_args()

    if args.record:
        network, raw_stamp = args.record
        if not raw_stamp.isdigit():
            parser.error("EPOCH_MS must be an integer")
        stamp = int(raw_stamp)
    else:
        network = network_from_ini(BRIDGE_INI)
        if network is None:
            print("NOTICE: MMDVM_Bridge DMR address is not recognized as BM or TGIF; no history entry added.")
            return
        if args.current:
            try:
                # The INI is atomically replaced before the bridge restarts.
                # Let the watcher timestamp the transition at observation time
                # so it cannot predate the button's successful switch event.
                stamp = time.time_ns() // 1_000_000
            except OSError:
                print("NOTICE: MMDVM_Bridge.ini is unavailable; no history entry added.")
                return
        else:
            stamp = time.time_ns() // 1_000_000

    changed = record(network, stamp)
    if changed:
        print(f"PASS: recorded {network} DMR network event at {stamp} ms.")
    else:
        print(f"PASS: {network} is already the recorded network at {stamp} ms; no duplicate event added.")


if __name__ == "__main__":
    main()
