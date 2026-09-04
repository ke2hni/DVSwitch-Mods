#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

"""Patch supported DVSwitch activity tables for cleaned Target display."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

MARKER = "// DVSwitch-Mods: cleaned activity Target display v1"
INCLUDE = "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_target_display.php';"
SUPPORTED = {
    "lh.php": {
        "fc656bfec498ed3e9fd8738238207e25a7cd3911b0ea7fba7001e52095e807da",
        "2a9b4510fcf5adf0b5bd479ac9027a8dbeba2835f7068656b38dd36d7c280953",
        "4ba94a4dfe796c8c23ed0f8df7c585c019ed464e85e0057e529884ffd77a4af8",
    },
    "localtx.php": {
        "2cbd0c26fa58fe0887f6b95e70cb222f6b5aaaf2e23f79dd0545aad64ba5f336",
        "376b4d5ba19b19ae17173487e2e51e3ba6554e38700aae47bf1142357fd9c435",
        "23ba44628248f6000222adb4e4bde67d38aef9f10f136c3c62b820c4fee53ee4",
    },
}


class PatchError(RuntimeError):
    pass


def digest(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def replacement(name: str) -> tuple[str, str]:
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
    else:
        old = r'''\t\t\tif (strlen($listElem[4]) == 1) { $listElem[4] = str_pad($listElem[4], 8, " ", STR_PAD_LEFT); }
\t\t\techo"<td align=\"left\">&nbsp;<span style=\"color:#b5651d;font-weight:bold;\">".str_replace(" ","&nbsp;", $listElem[4])."</span></td>";
'''.replace("\\t", "\t")
        new = '''\t\t\t$dvsModsTarget = dvsModsTargetDisplay($listElem[1], $listElem[4], $listElem[6]);
\t\t\techo '<td align="left">&nbsp;<span style="color:#b5651d;font-weight:bold;white-space:normal;">'.htmlspecialchars($dvsModsTarget, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").'</span></td>';
'''
    return old, new


def patch_text(text: str, name: str) -> str:
    old, new = replacement(name)
    if text.count(MARKER) == 1:
        if text.count(INCLUDE) != 1 or text.count(new) != 1:
            raise PatchError(f"incomplete modified {name}")
        recovered = text.replace(MARKER + "\n", "", 1).replace(INCLUDE + "\n", "", 1).replace(new, old, 1)
        if digest(recovered) not in SUPPORTED[name]:
            raise PatchError(f"unsupported modified {name} hash: {digest(text)}")
        return text
    if MARKER in text or INCLUDE in text or "dvsModsTargetDisplay(" in text:
        raise PatchError(f"partial or duplicate modification in {name}")
    if digest(text) not in SUPPORTED[name]:
        raise PatchError(f"unsupported unmodified {name} hash: {digest(text)}")
    if text.count(old) != 1:
        raise PatchError(f"unsupported or ambiguous Target block in {name}: {text.count(old)} matches")
    if not text.startswith("<?php\n"):
        raise PatchError(f"unsupported marker anchor in {name}")
    include_anchor = "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_fcc_first_names.php';\n"
    if text.count(include_anchor) != 1:
        raise PatchError(f"unsupported include anchor in {name}")
    text = text.replace("<?php\n", "<?php\n" + MARKER + "\n", 1)
    text = text.replace(include_anchor, include_anchor + INCLUDE + "\n", 1)
    return text.replace(old, new, 1)


def patch_file(path: Path) -> None:
    raw = path.read_bytes()
    if b"\r\n" in raw and raw.count(b"\r\n") == raw.count(b"\n"):
        newline = "\r\n"
    elif b"\r" not in raw:
        newline = "\n"
    else:
        raise PatchError(f"unsupported mixed line endings in {path.name}")
    text = raw.decode("utf-8").replace("\r\n", "\n")
    result = patch_text(text, path.name)
    if newline == "\r\n":
        result = result.replace("\n", "\r\n")
    path.write_bytes(result.encode("utf-8"))


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
