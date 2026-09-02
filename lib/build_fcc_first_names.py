#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

"""Build a compact fixed-record FCC amateur callsign/first-name database."""

from __future__ import annotations

import argparse
import csv
import re
import sqlite3
import tempfile
import unicodedata
import zipfile
from pathlib import Path

RECORD_SIZE = 52
MIN_PRODUCTION_RECORDS = 700_000
CALL_RE = re.compile(r"^[A-Z0-9]{3,10}$")


class BuildError(RuntimeError):
    pass


def ascii_name(value: str) -> str:
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    value = " ".join(value.strip().split())
    if value.isupper() or value.islower():
        value = value.title()
    value = "".join(ch for ch in value if ch.isalnum() or ch in " .'-")
    return value[:40].strip()


def pipe_rows(stream):
    text = (line.decode("latin-1").rstrip("\r\n") for line in stream)
    yield from csv.reader(text, delimiter="|")


def build(archive: Path, output: Path, minimum: int = MIN_PRODUCTION_RECORDS) -> int:
    if not archive.is_file() or archive.is_symlink():
        raise BuildError("archive is not a regular non-symlink file")
    try:
        zf = zipfile.ZipFile(archive)
        bad = zf.testzip()
        if bad:
            raise BuildError(f"ZIP integrity failure: {bad}")
        names = set(zf.namelist())
        expected_files = {"counts", "AM.dat", "CO.dat", "EN.dat", "HD.dat", "HS.dat", "LA.dat", "SC.dat", "SF.dat"}
        if names != expected_files:
            raise BuildError("archive does not contain the exact nine expected FCC files")
        counts_text = zf.read("counts").decode("latin-1")
        if "File Creation Date:" not in counts_text or "HD.dat" not in counts_text or "EN.dat" not in counts_text:
            raise BuildError("invalid FCC counts file")
        expected_counts = {name: int(value) for value, name in re.findall(r"^\s*(\d+)\s+\S*/(\w+\.dat)\s*$", counts_text, re.MULTILINE)}
        if "HD.dat" not in expected_counts or "EN.dat" not in expected_counts:
            raise BuildError("counts file lacks HD.dat or EN.dat totals")

        with tempfile.TemporaryDirectory(prefix="fcc-first-names-", dir=output.parent) as work:
            database = Path(work) / "records.sqlite3"
            connection = sqlite3.connect(database)
            connection.execute("PRAGMA journal_mode=OFF")
            connection.execute("PRAGMA synchronous=OFF")
            connection.execute("CREATE TABLE active (system_id TEXT PRIMARY KEY, callsign TEXT UNIQUE NOT NULL, first_name TEXT)")

            active = []
            hd_rows = 0
            with zf.open("HD.dat") as source:
                for row in pipe_rows(source):
                    hd_rows += 1
                    if len(row) < 6 or row[5] != "A":
                        continue
                    system_id, callsign = row[1].strip(), row[4].strip().upper()
                    if system_id and CALL_RE.fullmatch(callsign):
                        active.append((system_id, callsign))
                    if len(active) >= 50_000:
                        connection.executemany("INSERT INTO active(system_id,callsign) VALUES (?,?)", active)
                        active.clear()
            if active:
                connection.executemany("INSERT INTO active(system_id,callsign) VALUES (?,?)", active)
            connection.commit()
            if hd_rows != expected_counts["HD.dat"]:
                raise BuildError(f"HD.dat has {hd_rows} records; counts declares {expected_counts['HD.dat']}")

            updates = []
            en_rows = 0
            with zf.open("EN.dat") as source:
                for row in pipe_rows(source):
                    en_rows += 1
                    if len(row) < 10:
                        continue
                    first = ascii_name(row[8])
                    if first:
                        updates.append((first, row[1].strip()))
                    if len(updates) >= 50_000:
                        connection.executemany("UPDATE active SET first_name=? WHERE system_id=?", updates)
                        updates.clear()
            if updates:
                connection.executemany("UPDATE active SET first_name=? WHERE system_id=?", updates)
            connection.commit()
            if en_rows != expected_counts["EN.dat"]:
                raise BuildError(f"EN.dat has {en_rows} records; counts declares {expected_counts['EN.dat']}")

            total = connection.execute("SELECT COUNT(*) FROM active WHERE first_name IS NOT NULL AND first_name != ''").fetchone()[0]
            if total < minimum:
                raise BuildError(f"only {total} active callsigns have first names; minimum is {minimum}")

            candidate = Path(work) / "fcc-first-names.dat"
            with candidate.open("wb") as target:
                for callsign, first in connection.execute(
                    "SELECT callsign, first_name FROM active WHERE first_name IS NOT NULL AND first_name != '' ORDER BY callsign"
                ):
                    record = f"{callsign:<10}|{first:<40}\n".encode("ascii")
                    if len(record) != RECORD_SIZE:
                        raise BuildError("generated a non-fixed-width record")
                    target.write(record)
            connection.close()
            validate(candidate, minimum)
            candidate.replace(output)
            return total
    except (OSError, csv.Error, sqlite3.Error, zipfile.BadZipFile) as exc:
        raise BuildError(str(exc)) from exc


def validate(path: Path, minimum: int = MIN_PRODUCTION_RECORDS) -> int:
    size = path.stat().st_size
    if size % RECORD_SIZE:
        raise BuildError("database size is not a multiple of the fixed record size")
    count = size // RECORD_SIZE
    if count < minimum:
        raise BuildError(f"database contains only {count} records; minimum is {minimum}")
    previous = ""
    with path.open("rb") as source:
        for number, raw in enumerate(source, 1):
            if len(raw) != RECORD_SIZE or raw[10:11] != b"|" or raw[-1:] != b"\n":
                raise BuildError(f"invalid fixed record at line {number}")
            callsign = raw[:10].decode("ascii").rstrip()
            first = raw[11:51].decode("ascii").rstrip()
            if not CALL_RE.fullmatch(callsign) or not first or callsign <= previous:
                raise BuildError(f"invalid or unsorted record at line {number}")
            previous = callsign
    return count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--validate", type=Path)
    parser.add_argument("--minimum", type=int, default=MIN_PRODUCTION_RECORDS)
    args = parser.parse_args()
    if args.validate:
        print(validate(args.validate, args.minimum))
    elif args.archive and args.output:
        print(build(args.archive, args.output, args.minimum))
    else:
        parser.error("use --validate FILE or --archive ZIP --output FILE")


if __name__ == "__main__":
    try:
        main()
    except BuildError as exc:
        raise SystemExit(f"ERROR: FCC first-name database build failed: {exc}")
