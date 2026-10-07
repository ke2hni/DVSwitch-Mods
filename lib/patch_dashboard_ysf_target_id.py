#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Show the YSF host ID below its friendly room name on the status card."""

from __future__ import annotations

import argparse
from pathlib import Path
import re

MARKER = "// DVSwitch-Mods: YSF card target ID v1"
LINKED = "                $ysfLinkedToTxt = $ysfLinkedTo;"
HOST_NAME = "                                $ysfLinkedToTxt = $ysfRoomTxtLine[1];"
OUTPUT = "$ysfLinkedToTxt = str_replace('_', ' ', $ysfLinkedToTxt);"
ID_ASSIGNMENT = "                                $ysfLinkedToId = trim($ysfRoomTxtLine[0]);"
ID_RENDER = '''            if ($ysfLinkedToId !== "" && $ysfLinkedToId !== "null") {
                $ysfLinkedToTxt .= "<br/><span style=\\"color:#b5651d;font-weight:bold;white-space:normal;word-break:normal;overflow-wrap:anywhere;text-align:center;\\">(ID ".htmlspecialchars($ysfLinkedToId, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").")</span>";
            }
'''


class PatchError(RuntimeError):
    pass


def once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise PatchError(f"unsupported or ambiguous {label}: {count} matches")
    return text.replace(old, new, 1)


def patch(text: str) -> str:
    if MARKER in text:
        if (text.count(MARKER) != 1 or text.count(ID_ASSIGNMENT) != 1
                or text.count('htmlspecialchars($ysfLinkedToId, ENT_QUOTES') != 1
                or text.count('(ID ".htmlspecialchars($ysfLinkedToId') != 1):
            raise PatchError("partial or duplicate YSF card target-ID patch")
        return text
    if text.count(LINKED) != 1 or text.count(HOST_NAME) != 1 or text.count(OUTPUT) != 1:
        raise PatchError("YSF dashboard target-ID anchors are missing or ambiguous; install YSF dashboard repair first")
    text = once(text, LINKED, LINKED + "\n                $ysfLinkedToId = \"\";", "YSF linked-name initialization")
    text = once(text, HOST_NAME, HOST_NAME + "\n" + ID_ASSIGNMENT, "YSF host ID capture")
    output_pattern = re.compile(r"(?m)^([\t ]*)" + re.escape(OUTPUT) + r"$")
    output_matches = list(output_pattern.finditer(text))
    if len(output_matches) != 1:
        raise PatchError(f"unsupported or ambiguous YSF target ID rendering: {len(output_matches)} matches")
    match = output_matches[0]
    indent = match.group(1)
    rendered = "\n".join(indent + line if line else "" for line in ID_RENDER.rstrip("\n").split("\n"))
    replacement = indent + MARKER + "\n" + rendered + "\n" + indent + OUTPUT
    text = text[:match.start()] + replacement + text[match.end():]
    return text


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("status", type=Path)
    args = parser.parse_args()
    raw = args.status.read_bytes()
    if b"\r" in raw.replace(b"\r\n", b""):
        raise PatchError("mixed line endings are unsupported")
    newline = "\r\n" if b"\r\n" in raw else "\n"
    text = raw.decode("utf-8").replace("\r\n", "\n")
    args.status.write_text(patch(text).replace("\n", newline), encoding="utf-8", newline="")


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, PatchError) as error:
        raise SystemExit(f"ERROR: {error}")
