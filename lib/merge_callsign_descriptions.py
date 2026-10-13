#!/usr/bin/env python3
"""Append missing starter custom descriptions without replacing user data."""
from __future__ import annotations

import fcntl
import os
import re
import stat
import sys
from pathlib import Path

IDENTIFIER_RE = re.compile(r"^[A-Z0-9]+(?:-[A-Z0-9]+)*$")
CONTROL_RE = re.compile(r"[\x00-\x1f\x7f]")


def parse_entry(line: str) -> tuple[str, str] | None:
    text = line.strip()
    if not text or text.startswith("#"):
        return None
    separator = text.find("=")
    if separator < 0:
        separator = text.find("\t")
    if separator < 0:
        return None
    identifier = text[:separator].strip().upper()
    if not IDENTIFIER_RE.fullmatch(identifier) or len(identifier) > 16:
        return None
    return identifier, text[separator + 1 :].strip()


def validate_description(value: str, path: Path, number: int) -> None:
    if not value or len(value) > 80 or CONTROL_RE.search(value) or "=" in value:
        raise ValueError(f"invalid starter description at {path}:{number}")


def load_starter(path: Path) -> list[tuple[str, str]]:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise ValueError(f"cannot read starter file {path}: {exc}") from exc
    entries: list[tuple[str, str]] = []
    seen: set[str] = set()
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        entry = parse_entry(line)
        if entry is None:
            raise ValueError(f"invalid starter entry at {path}:{number}")
        identifier, description = entry
        validate_description(description, path, number)
        if identifier not in seen:
            entries.append((identifier, description))
            seen.add(identifier)
    return entries


def check_target(path: Path) -> None:
    if path.is_symlink():
        raise ValueError(f"refusing symbolic-link target: {path}")
    if path.exists() and not path.is_file():
        raise ValueError(f"target is not a regular file: {path}")


def present_identifiers(data: bytes) -> set[str]:
    result: set[str] = set()
    for line in data.decode("utf-8", errors="replace").splitlines():
        entry = parse_entry(line)
        if entry is not None:
            result.add(entry[0])
    return result


def missing_entries(data: bytes, starter: list[tuple[str, str]]) -> list[tuple[str, str]]:
    present = present_identifiers(data)
    return [entry for entry in starter if entry[0] not in present]


def merge(target: Path, starter: list[tuple[str, str]]) -> int:
    check_target(target)
    flags = os.O_RDWR | os.O_CREAT | os.O_APPEND
    flags |= getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(target, flags, 0o660)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise ValueError(f"target is not a regular file: {target}")
        os.lseek(descriptor, 0, os.SEEK_SET)
        chunks: list[bytes] = []
        while True:
            chunk = os.read(descriptor, 65536)
            if not chunk:
                break
            chunks.append(chunk)
        original = b"".join(chunks)
        additions = missing_entries(original, starter)
        if not additions:
            return 0
        separator = b"" if not original or original.endswith((b"\n", b"\r")) else b"\n"
        appended = "".join(f"{identifier} = {description}\n" for identifier, description in additions).encode("utf-8")
        payload = separator + appended
        original_size = len(original)
        try:
            view = memoryview(payload)
            while view:
                count = os.write(descriptor, view)
                if count <= 0:
                    raise OSError("short write while appending starter entries")
                view = view[count:]
            os.fsync(descriptor)
        except OSError:
            os.ftruncate(descriptor, original_size)
            os.fsync(descriptor)
            raise
        return len(additions)
    finally:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        finally:
            os.close(descriptor)


def main(argv: list[str]) -> int:
    if len(argv) != 4 or argv[1] not in {"--check", "--merge"}:
        print(f"Usage: {argv[0]} {{--check|--merge}} TARGET STARTER", file=sys.stderr)
        return 2
    operation, target, starter_path = argv[1], Path(argv[2]), Path(argv[3])
    try:
        check_target(target)
        starter = load_starter(starter_path)
        if operation == "--check":
            current = target.read_bytes() if target.exists() else b""
            print(len(missing_entries(current, starter)))
        else:
            print(merge(target, starter))
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
