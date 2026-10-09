#!/usr/bin/env python3
# Version: 1.0.0
# SPDX-License-Identifier: MIT

"""Preserve MMDVM milliseconds and label Gateway DMR rows from BM/TGIF events."""

from __future__ import annotations

import argparse
from pathlib import Path
import re

FUNCTIONS_MARKER = "// DVSwitch-Mods: retain MMDVM log millisecond timestamps v1"
OLD_MARKER = "// DVSwitch-Mods: dashboard activity network labels v1"
LH_MARKER = "// DVSwitch-Mods: Gateway Activity DMR network labels v1"
INCLUDE = "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_activity_mode.php';"
ORIGINAL_CELL = 'echo"<td align=\\"left\\" style=\\"color:green; font-weight:bold;\\">&nbsp;$listElem[1]</td>";'
UNPADDED_CELL = ORIGINAL_CELL.replace(">&nbsp;$listElem[1]", ">$listElem[1]")
OLD_BEFORE = "$dvsModsActivityOriginalMode = $listElem[1];\n$listElem[1] = dvsModsActivityModeLabel($listElem[1], $listElem[0]);\n"
OLD_AFTER = "\n$listElem[1] = $dvsModsActivityOriginalMode;"
NEW_BEFORE = "$dvsModsActivityOriginalMode = $listElem[1];\n$listElem[1] = dvsModsActivityModeLabel($listElem[1], $listElem[0], $listElem[5]);\n"
NEW_AFTER = OLD_AFTER
LOG_LINE_VARIABLE = "$logLine"


class PatchError(RuntimeError):
    pass


def patch_functions(text: str) -> str:
    if text.count(FUNCTIONS_MARKER) == 1:
        start = text.find("function getHeardList(")
        end = text.find("function getLastHeard(", start + 1)
        region = text[start:end] if start >= 0 and end >= 0 else ""
        if re.search(r"\$timestamp = substr\(\$logLines?, 3, 19\);", region) or len(re.findall(r"\$timestamp = substr\(\$logLines?, 3, 23\);", region)) != 2:
            raise PatchError("partial MMDVM millisecond timestamp modification in functions.php")
        return text
    if FUNCTIONS_MARKER in text:
        raise PatchError("duplicate MMDVM millisecond timestamp marker in functions.php")
    start = text.find("function getHeardList(")
    end = text.find("function getLastHeard(", start + 1)
    if start < 0 or end < 0:
        raise PatchError("could not locate getHeardList() in functions.php")
    region = text[start:end]
    old_parser = "$timestamp = substr($logLines, 3, 19);"
    new_parser = "$timestamp = substr($logLines, 3, 23);"
    parser_variable = "$logLines" if region.count(old_parser) == 2 else LOG_LINE_VARIABLE
    old_parser = f"$timestamp = substr({parser_variable}, 3, 19);"
    new_parser = f"$timestamp = substr({parser_variable}, 3, 23);"
    if region.count(old_parser) != 2 or new_parser in region:
        raise PatchError("expected exactly two original activity timestamp parsers in getHeardList()")
    region = region.replace(old_parser, new_parser)
    text = text[:start] + region + text[end:]
    return text.replace("function getHeardList(", FUNCTIONS_MARKER + "\nfunction getHeardList(", 1)


def _remove_old_wrapper(text: str, name: str) -> str:
    cells = (ORIGINAL_CELL, UNPADDED_CELL)
    matches = [cell for cell in cells if text.count(OLD_BEFORE + cell + OLD_AFTER) == 1]
    if len(matches) != 1:
        raise PatchError(f"legacy activity-mode wrapper is missing or ambiguous in {name}")
    wrapped = OLD_BEFORE + matches[0] + OLD_AFTER
    return text.replace(wrapped, matches[0], 1)


def patch_lh(text: str) -> str:
    if text.count(LH_MARKER) == 1:
        if text.count(INCLUDE) != 1 or text.count(NEW_BEFORE) != 1 or OLD_MARKER in text:
            raise PatchError("incomplete or ambiguous Gateway Activity DMR label patch")
        return text
    if text.count(LH_MARKER) > 1:
        raise PatchError("duplicate Gateway Activity DMR label marker")

    if OLD_MARKER in text:
        if text.count(OLD_MARKER) != 1:
            raise PatchError("duplicate legacy activity-mode marker in lh.php")
        text = _remove_old_wrapper(text, "lh.php")
        text = text.replace(OLD_MARKER, LH_MARKER, 1)
    else:
        if "dvsModsActivityModeLabel(" in text:
            raise PatchError("unmarked or partial activity-mode wrapper in lh.php")
        if not text.startswith("<?php\n"):
            raise PatchError("unsupported PHP opening in lh.php")
        text = text.replace("<?php\n", "<?php\n" + LH_MARKER + "\n", 1)

    if text.count(INCLUDE) == 0:
        anchors = (
            "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_target_display.php';",
            "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_fcc_first_names.php';",
            "include_once dirname(dirname(__FILE__)).'/include/functions.php';",
        )
        anchor = next((item for item in anchors if text.count(item) == 1), None)
        if anchor is None:
            raise PatchError("could not find a unique helper include anchor in lh.php")
        text = text.replace(anchor, anchor + "\n" + INCLUDE, 1)
    if text.count(INCLUDE) != 1:
        raise PatchError("activity helper include is ambiguous in lh.php")

    cells = (ORIGINAL_CELL, UNPADDED_CELL)
    found = [cell for cell in cells if text.count(cell) == 1]
    if len(found) != 1:
        raise PatchError("could not find the original Gateway Activity Mode cell exactly once")
    cell = found[0]
    return text.replace(cell, NEW_BEFORE + cell + NEW_AFTER, 1)


def clean_localtx(text: str) -> str:
    if OLD_MARKER not in text:
        if "dvsModsActivityModeLabel(" in text:
            raise PatchError("unmarked or partial legacy activity-mode wrapper in localtx.php")
        return text
    if text.count(OLD_MARKER) != 1:
        raise PatchError("duplicate legacy activity-mode marker in localtx.php")
    text = _remove_old_wrapper(text, "localtx.php")
    text = text.replace(OLD_MARKER + "\n", "", 1)
    if text.count(INCLUDE) != 1:
        raise PatchError("legacy activity helper include is missing or ambiguous in localtx.php")
    return text.replace(INCLUDE + "\n", "", 1)


def patch_file(path: Path, transform) -> None:
    raw = path.read_bytes()
    if b"\r" in raw.replace(b"\r\n", b""):
        raise PatchError(f"unsupported mixed line endings in {path}")
    newline = "\r\n" if b"\r\n" in raw else "\n"
    text = raw.decode("utf-8").replace("\r\n", "\n")
    path.write_bytes(transform(text).replace("\n", newline).encode("utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--functions", type=Path, required=True)
    parser.add_argument("--lh", type=Path, required=True)
    parser.add_argument("--localtx", type=Path, required=True)
    args = parser.parse_args()
    patch_file(args.functions, patch_functions)
    patch_file(args.lh, patch_lh)
    patch_file(args.localtx, clean_localtx)


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, PatchError) as error:
        raise SystemExit(f"ERROR: {error}")
