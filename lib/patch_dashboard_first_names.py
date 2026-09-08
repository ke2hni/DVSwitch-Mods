#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Surgically add FCC/worldwide names to Gateway Activity (lh.php)."""

from __future__ import annotations

import argparse
from pathlib import Path

LEGACY_MARKER = "// DVSwitch-Mods: FCC first-name activity columns v1"
MARKER = "// DVSwitch-Mods: FCC first-name activity columns v2"
INCLUDE = "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_fcc_first_names.php';"


class PatchError(RuntimeError):
    pass


def once(text: str, old: str, new: str, description: str) -> str:
    count = text.count(old)
    if count != 1:
        raise PatchError(f"unsupported or ambiguous {description}: {count} matches")
    return text.replace(old, new, 1)


def patch_text(text: str) -> str:
    if text.count(MARKER) == 1:
        required = (INCLUDE, "dvsModsFccFirstName($listElem[2])",
                    "dvsModsDmrIdCallsign($listElem[2])", "<th>Name</th>")
        if any(text.count(token) != 1 for token in required):
            raise PatchError("incomplete FCC Gateway Activity modification")
        return text
    if text.count(MARKER) > 1 or text.count(LEGACY_MARKER) > 1:
        raise PatchError("duplicate FCC modification marker")
    if text.count(LEGACY_MARKER) == 1:
        return text.replace(LEGACY_MARKER, MARKER, 1)
    if MARKER in text or LEGACY_MARKER in text:
        raise PatchError("partial FCC modification marker")
    if not text.startswith("<?php\n"):
        raise PatchError("unsupported lh.php PHP anchor")

    text = text.replace("<?php\n", "<?php\n" + MARKER + "\n", 1)
    text = once(text,
        "include_once dirname(dirname(__FILE__)).'/include/functions.php';    \n",
        "include_once dirname(dirname(__FILE__)).'/include/functions.php';    \n" + INCLUDE + "\n",
        "Gateway Activity include anchor")
    text = once(text, "      <th>Time (<?php echo date('T')?>)</th>",
                "      <th style=\"white-space:nowrap;width:115px;\">Time (<?php echo date('T')?>)</th>",
                "Gateway Activity time header")
    old_header = '''      <th>Callsign</th>
<?php
    if (DISPLAYNAME == "YES" && file_exists(DMRIDDATPATH."/DMRIds.dat") && ! empty(DMRIDDATPATH."/DMRIds.dat")) { echo "<th>Name</th>"; }
?>'''
    text = once(text, old_header, "      <th>Callsign</th>\n      <th>Name</th>", "Gateway Activity name header")
    start_token = "// Display NAME by DV8AWC"
    end_tokens = ["if (strlen($listElem[4]) == 1)",
                  "$dvsModsTarget = dvsModsTargetDisplay($listElem[1], $listElem[4], $listElem[6]);"]
    end_token = next((token for token in end_tokens if text.count(token) == 1), None)
    if text.count(start_token) != 1 or end_token is None:
        raise PatchError("unsupported or ambiguous Gateway Activity name block")
    start = text.rfind("\n", 0, text.index(start_token)) + 1
    end = text.rfind("\n", 0, text.index(end_token)) + 1
    if start >= end:
        raise PatchError("invalid Gateway Activity name-block order")
    replacement = '''                $dvsModsFirstName = dvsModsFccFirstName($listElem[2]);
                echo '<td align="left" style="font-weight:bold;color:#464646;">&nbsp;<b>'.htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").'</b></td>';
'''
    text = text[:start] + replacement + text[end:]
    token = 'if ((is_numeric($listElem[2]) || strpos($listElem[2], "openSPOT") !== FALSE)'
    if text.count(token) != 1:
        raise PatchError(f"unsupported or ambiguous Gateway Activity callsign anchor: {text.count(token)} matches")
    insertion = text.rfind("\n", 0, text.index(token)) + 1
    indent = text[insertion:text.index(token)]
    return text[:insertion] + indent + "$listElem[2] = dvsModsDmrIdCallsign($listElem[2]);\n" + text[insertion:]


def patch_file(path: Path) -> None:
    raw = path.read_bytes()
    if b"\r" in raw.replace(b"\r\n", b""):
        raise PatchError(f"unsupported mixed line endings in {path}")
    newline = "\r\n" if b"\r\n" in raw else "\n"
    result = patch_text(raw.decode("utf-8").replace("\r\n", "\n"))
    path.write_bytes(result.replace("\n", newline).encode("utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lh", type=Path, required=True)
    args = parser.parse_args()
    if args.lh.name != "lh.php":
        raise PatchError("FCC patcher accepts only lh.php; Local Activity is intentionally untouched")
    patch_file(args.lh)


if __name__ == "__main__":
    try:
        main()
    except PatchError as exc:
        raise SystemExit(f"ERROR: {exc}")
