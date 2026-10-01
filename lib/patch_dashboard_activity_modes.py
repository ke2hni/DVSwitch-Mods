#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Surgically label current DMR activity with its selected DVSwitch network."""

from __future__ import annotations

import argparse
from pathlib import Path

MARKER = "// DVSwitch-Mods: dashboard activity network labels v1"
INCLUDE = "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_activity_mode.php';"
MODE_CELL = {
    "lh.php": 'echo"<td align=\\"left\\" style=\\"color:green; font-weight:bold;\\">&nbsp;$listElem[1]</td>";',
    "localtx.php": 'echo"<td align=\\"left\\" style=\\"color:green; font-weight:bold;\\">&nbsp;$listElem[1]</td>";',
}
MODE_CELL_PADDED = {
    name: value.replace(">&nbsp;$listElem[1]", ">$listElem[1]")
    for name, value in MODE_CELL.items()
}
WRAP_BEFORE = '''$dvsModsActivityOriginalMode = $listElem[1];
$listElem[1] = dvsModsActivityModeLabel($listElem[1], $listElem[0]);
'''
WRAP_AFTER = '''
$listElem[1] = $dvsModsActivityOriginalMode;'''


class PatchError(RuntimeError):
    pass


def patch_text(text: str, name: str) -> str:
    if name not in MODE_CELL:
        raise PatchError(f"unsupported activity file: {name}")

    marker_count = text.count(MARKER)
    include_count = text.count(INCLUDE)
    wrapped_count = sum(text.count(WRAP_BEFORE + cell + WRAP_AFTER) for cell in (MODE_CELL[name], MODE_CELL_PADDED[name]))
    if marker_count == 1:
        if include_count != 1 or wrapped_count != 1:
            raise PatchError(f"incomplete or ambiguous activity-mode modification in {name}")
        return text
    if marker_count or include_count or "dvsModsActivityModeLabel(" in text:
        raise PatchError(f"partial or duplicate activity-mode modification in {name}")

    candidates = [MODE_CELL[name], MODE_CELL_PADDED[name]]
    found = [cell for cell in candidates if text.count(cell) == 1]
    if len(found) != 1:
        counts = ", ".join(f"{cell!r}: {text.count(cell)}" for cell in candidates)
        raise PatchError(f"unsupported or ambiguous Mode cell in {name} ({counts})")
    if not text.startswith("<?php\n"):
        raise PatchError(f"unsupported PHP anchor in {name}")

    include_anchors = (
        "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_target_display.php';",
        "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_fcc_first_names.php';",
        "include_once dirname(dirname(__FILE__)).'/include/functions.php';",
    )
    if any(text.count(anchor) > 1 for anchor in include_anchors):
        raise PatchError(f"unsupported or ambiguous include anchor in {name}")
    anchor = next((candidate for candidate in include_anchors if text.count(candidate) == 1), None)
    if anchor is None:
        raise PatchError(f"unsupported or ambiguous include anchor in {name}")

    cell = found[0]
    wrapped = WRAP_BEFORE + cell + WRAP_AFTER
    text = text.replace("<?php\n", "<?php\n" + MARKER + "\n", 1)
    text = text.replace(anchor, anchor + "\n" + INCLUDE, 1)
    text = text.replace(cell, wrapped, 1)
    return text


def patch_file(path: Path) -> None:
    raw = path.read_bytes()
    if b"\r" in raw.replace(b"\r\n", b""):
        raise PatchError(f"unsupported mixed line endings in {path}")
    newline = "\r\n" if b"\r\n" in raw else "\n"
    text = raw.decode("utf-8").replace("\r\n", "\n")
    path.write_bytes(patch_text(text, path.name).replace("\n", newline).encode("utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lh", type=Path, required=True)
    parser.add_argument("--localtx", type=Path, required=True)
    args = parser.parse_args()
    patch_file(args.lh)
    patch_file(args.localtx)


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, PatchError) as error:
        raise SystemExit(f"ERROR: {error}")
