#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Surgically add D-Star Tx TG/reflector display to status.php."""

from __future__ import annotations

import argparse
from pathlib import Path

MARKER = "// DVSwitch-Mods: D-Star Tx TG/Ref display v1"

INSERT_ANCHOR = "    $abinfo = getABInfo('/tmp/ABInfo_'.ABINFO.'.json');\n"
INSERTION = '''    // DVSwitch-Mods: D-Star Tx TG/Ref display v1
    $txValue = $abinfo['digital']['tg'];
    if ($abinfo['tlv']['ambe_mode'] == "DSTAR") {
        $txValue = preg_replace('/^(Linked to|Linking to)\\s+/i', '', trim(strip_tags(str_replace("<br />", " ", getDSTARLinks()))));
        $txValue = preg_replace('/\\s*\\(.*\\)\\s*$/', '', $txValue);
    }
'''

TOOLTIP_OLD = '''    echo "<br>&nbsp;&nbsp;&nbsp;txTG: ".$abinfo['digital']['tg'];'''
TOOLTIP_NEW = '''    echo "<br>&nbsp;&nbsp;&nbsp;txTG: ".$txValue;'''

ROW_OLD = '''    echo "<tr><th width=50%>Tx TG</th><td style=\\"background: #f9f9f9;font-weight: bold;color:#ef7215;\\">".$abinfo['digital']['tg']."</td></tr>\\n";'''
ROW_NEW = '''    echo "<tr><th width=50%>Tx TG/Ref</th><td style=\\"background: #f9f9f9;font-weight: bold;color:#ef7215;\\">".$txValue."</td></tr>\\n";'''


class PatchError(RuntimeError):
    pass


def once(text: str, old: str, new: str, description: str) -> str:
    count = text.count(old)
    if count != 1:
        raise PatchError(f"unsupported or ambiguous {description}: {count} matches")
    return text.replace(old, new, 1)


def patch_text(text: str) -> str:
    marker_count = text.count(MARKER)
    if marker_count > 1:
        raise PatchError("duplicate D-Star marker")
    if marker_count == 1:
        if text.count(INSERTION) != 1 or text.count(TOOLTIP_NEW) != 1 or text.count(ROW_NEW) != 2:
            raise PatchError("incomplete or ambiguous D-Star modification")
        if text.count(TOOLTIP_OLD) or text.count(ROW_OLD):
            raise PatchError("mixed D-Star modification state")
        return text

    if text.count(INSERTION) or text.count(TOOLTIP_NEW) or text.count(ROW_NEW):
        raise PatchError("partial D-Star modification")
    text = once(text, INSERT_ANCHOR, INSERT_ANCHOR + INSERTION, "D-Star insertion anchor")
    text = once(text, TOOLTIP_OLD, TOOLTIP_NEW, "D-Star tooltip")
    if text.count(ROW_OLD) != 2:
        raise PatchError(f"unsupported or ambiguous D-Star Tx rows: {text.count(ROW_OLD)} matches")
    text = text.replace(ROW_OLD, ROW_NEW)
    return text


def patch_file(path: Path) -> None:
    raw = path.read_bytes()
    if b"\r" in raw.replace(b"\r\n", b""):
        raise PatchError(f"unsupported mixed line endings in {path}")
    newline = "\r\n" if b"\r\n" in raw else "\n"
    result = patch_text(raw.decode("utf-8").replace("\r\n", "\n"))
    path.write_bytes(result.replace("\n", newline).encode("utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--status", type=Path, required=True)
    args = parser.parse_args()
    if args.status.name != "status.php":
        raise PatchError("D-Star patcher accepts only status.php")
    patch_file(args.status)


if __name__ == "__main__":
    try:
        main()
    except PatchError as exc:
        raise SystemExit(f"ERROR: {exc}")
