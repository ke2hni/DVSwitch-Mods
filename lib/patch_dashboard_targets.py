#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Surgically add the cleaned Target display to DVSwitch activity tables."""

from __future__ import annotations

import argparse
from pathlib import Path

LEGACY_MARKER = "// DVSwitch-Mods: cleaned activity Target display v1"
MARKER = "// DVSwitch-Mods: cleaned activity Target display v2"
INCLUDE = "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_target_display.php';"
LEGEND = '''<div style="margin:3px auto 0 auto;font-size:10px;line-height:1.3;text-align:left;white-space:normal;overflow-wrap:anywhere;">
  <b>Legend:</b> <b>---</b> = no usable worldwide DMR or FCC name data available<br>
  <b>Talkgroups:</b> <b>Name (TG #)</b> = destination and talkgroup number<br>
  <b>YSF:</b> <b>Group Call</b> = call to ALL (room not recorded); <b>GPS/Data</b> = data transmission<br>
  <b>D-Star:</b> <b>General Call</b> = CQCQCQ (reflector not recorded)
</div>
'''


class PatchError(RuntimeError):
    pass


def block(name: str) -> tuple[str, str]:
    if name == "lh.php":
        old = r'''\t\tif (strlen($listElem[4]) == 1) { $listElem[4] = str_pad($listElem[4], 8, " ", STR_PAD_LEFT); }
\t\tif ( substr($listElem[4], 0, 6) === 'CQCQCQ' ) {
\t\t\techo "<td align=\"left\">&nbsp;<span style=\"color:#b5651d;font-weight:bold;\">$listElem[4]</span></td>";
\t\t} else {
\t\t\techo "<td align=\"left\">&nbsp;<span style=\"color:#b5651d;font-weight:bold;\">".str_replace(" ","&nbsp;", $listElem[4])."</span></td>";
\t\t}
'''.replace("\\t", "\t")
        new = '''\t\t$dvsModsTarget = dvsModsTargetDisplay($listElem[1], $listElem[4], $listElem[6]);
\t\techo '<td align="left">&nbsp;<span style="color:#b5651d;font-weight:bold;white-space:normal;">'.htmlspecialchars($dvsModsTarget, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").'</span></td>';
'''
    elif name == "localtx.php":
        old = r'''\t\t\tif (strlen($listElem[4]) == 1) { $listElem[4] = str_pad($listElem[4], 8, " ", STR_PAD_LEFT); }
\t\t\techo"<td align=\"left\">&nbsp;<span style=\"color:#b5651d;font-weight:bold;\">".str_replace(" ","&nbsp;", $listElem[4])."</span></td>";
'''.replace("\\t", "\t")
        new = '''\t\t\t$dvsModsTarget = dvsModsTargetDisplay($listElem[1], $listElem[4], $listElem[6]);
\t\t\techo '<td align="left">&nbsp;<span style="color:#b5651d;font-weight:bold;white-space:normal;">'.htmlspecialchars($dvsModsTarget, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").'</span></td>';
'''
    else:
        raise PatchError(f"unsupported dashboard file: {name}")
    return old, new


def once(text: str, old: str, new: str, description: str) -> str:
    count = text.count(old)
    if count != 1:
        raise PatchError(f"unsupported or ambiguous {description}: {count} matches")
    return text.replace(old, new, 1)


def patch_text(text: str, name: str) -> str:
    old, new = block(name)
    marker_count = text.count(MARKER) + text.count(LEGACY_MARKER)
    if marker_count > 1:
        raise PatchError(f"duplicate Target markers in {name}")
    if marker_count == 1:
        if text.count(INCLUDE) != 1 or text.count(new) != 1:
            raise PatchError(f"incomplete Target modification in {name}")
        if name == "localtx.php" and text.count(LEGEND) != 1:
            raise PatchError("incomplete Local Activity Target legend")
        return text.replace(LEGACY_MARKER, MARKER, 1)
    if MARKER in text or LEGACY_MARKER in text or INCLUDE in text or "dvsModsTargetDisplay(" in text:
        raise PatchError(f"partial Target modification in {name}")
    if text.count(old) != 1:
        raise PatchError(f"unsupported or ambiguous Target block in {name}: {text.count(old)} matches")
    if not text.startswith("<?php\n"):
        raise PatchError(f"unsupported PHP anchor in {name}")
    anchors = [
        "include_once dirname(dirname(__FILE__)).'/include/functions.php';    \n",
        "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_fcc_first_names.php';\n",
    ]
    anchor = next((candidate for candidate in anchors if text.count(candidate) == 1), None)
    if anchor is None:
        raise PatchError(f"unsupported include anchor in {name}")
    text = text.replace("<?php\n", "<?php\n" + MARKER + "\n", 1)
    text = text.replace(anchor, anchor + INCLUDE + "\n", 1)
    text = text.replace(old, new, 1)
    if name == "localtx.php":
        text = once(text, "</div>\n<br>", "</div>\n" + LEGEND + "<br>", "Local Activity legend anchor")
    return text


def patch_file(path: Path) -> None:
    raw = path.read_bytes()
    if b"\r" in raw.replace(b"\r\n", b""):
        raise PatchError(f"unsupported mixed line endings in {path}")
    newline = "\r\n" if b"\r\n" in raw else "\n"
    result = patch_text(raw.decode("utf-8").replace("\r\n", "\n"), path.name)
    path.write_bytes(result.replace("\n", newline).encode("utf-8"))


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
    except PatchError as exc:
        raise SystemExit(f"ERROR: {exc}")
