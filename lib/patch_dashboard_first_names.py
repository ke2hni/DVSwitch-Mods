#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

"""Patch supported DVSwitch activity tables for FCC first-name display."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

MARKER = "// DVSwitch-Mods: FCC first-name activity columns v1"
INCLUDE = "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_fcc_first_names.php';"
SUPPORTED = {
    "lh.php": {
        "f45377136d9163f835a89b8d628fb3c1bdd17005d34b5ed0a30e86fce0c9e45e",
        "44c49fa71aeeafcb82fe7237aceab990f0706e829d5b12ff7a3548ba189904fb",
    },
    "localtx.php": {
        "82b1b8077799748200904149eac1f18c3fdca0b35210b21640691d3a2de60206",
        "1b36452504c9d483eea618b4764da092a3f266b48ebf3c8d1095c6251ba823f7",
    },
}


class PatchError(RuntimeError):
    pass


def digest(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def replace_once(text: str, old: str, new: str, description: str) -> str:
    if text.count(old) != 1:
        raise PatchError(f"unsupported or ambiguous {description}: {text.count(old)} matches")
    return text.replace(old, new, 1)


def patch_lh(text: str) -> str:
    if not text.startswith("<?php\n"):
        raise PatchError("unsupported lh marker anchor")
    text = text.replace("<?php\n", "<?php\n" + MARKER + "\n", 1)
    text = replace_once(
        text,
        "include_once dirname(dirname(__FILE__)).'/include/functions.php';    \n",
        "include_once dirname(dirname(__FILE__)).'/include/functions.php';    \n" + INCLUDE + "\n",
        "lh include anchor",
    )
    text = replace_once(text, "      <th>Time (<?php echo date('T')?>)</th>", "      <th style=\"white-space:nowrap;width:140px;\">Time (<?php echo date('T')?>)</th>", "lh time header")
    old_header = '''      <th>Callsign</th>
<?php
    if (DISPLAYNAME == "YES" && file_exists(DMRIDDATPATH."/DMRIds.dat") && ! empty(DMRIDDATPATH."/DMRIds.dat")) { echo "<th>Name</th>"; }
?>'''
    text = replace_once(text, old_header, "      <th>Callsign</th>\n      <th>Name</th>", "lh stock name header")
    start = "                // Display NAME by DV8AWC\n"
    end = "                if (strlen($listElem[4]) == 1)"
    if text.count(start) != 1 or text.count(end) != 1:
        raise PatchError("unsupported or ambiguous lh stock name block")
    before, remainder = text.split(start, 1)
    _old, after = remainder.split(end, 1)
    replacement = '''                $dvsModsFirstName = dvsModsFccFirstName($listElem[2]);
                echo "<td align=\"left\" style=\"font-weight:bold;color:#464646;\">&nbsp;<b>".htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8')."</b></td>";
'''
    return before + replacement + end + after


def patch_localtx(text: str) -> str:
    if not text.startswith("<?php\n"):
        raise PatchError("unsupported localtx marker anchor")
    text = text.replace("<?php\n", "<?php\n" + MARKER + "\n", 1)
    text = replace_once(
        text,
        "include_once dirname(dirname(__FILE__)).'/include/functions.php';    \n",
        "include_once dirname(dirname(__FILE__)).'/include/functions.php';    \n" + INCLUDE + "\n",
        "localtx include anchor",
    )
    text = replace_once(text, "      <th>Time (<?php echo date('T')?>)</th>", "      <th style=\"white-space:nowrap;width:140px;\">Time (<?php echo date('T')?>)</th>", "localtx time header")
    text = replace_once(text, "      <th>Callsign</th>\n      <th>Target</th>", "      <th>Callsign</th>\n      <th>Name</th>\n      <th>Target</th>", "localtx name header")
    anchor = '''                    }
                        if (strlen($listElem[4]) == 1)'''
    replacement = '''                    }
                        $dvsModsFirstName = dvsModsFccFirstName($listElem[2]);
                        echo "<td align=\"left\" style=\"font-weight:bold;color:#464646;\">&nbsp;<b>".htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8')."</b></td>";
                        if (strlen($listElem[4]) == 1)'''
    return replace_once(text, anchor, replacement, "localtx callsign block")


def patch_text(text: str, name: str) -> str:
    if text.count(MARKER) == 1:
        if text.count(INCLUDE) != 1 or text.count("dvsModsFccFirstName($listElem[2])") != 1 or text.count("<th>Name</th>") != 1:
            raise PatchError(f"incomplete modified {name}")
        return text
    if MARKER in text:
        raise PatchError(f"duplicate markers in {name}")
    if digest(text) not in SUPPORTED[name]:
        raise PatchError(f"unsupported unmodified {name} hash: {digest(text)}")
    result = patch_lh(text) if name == "lh.php" else patch_localtx(text)
    if result.count(MARKER) != 1:
        raise PatchError(f"failed to install marker in {name}")
    return result


def patch_file(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    path.write_text(patch_text(text, path.name), encoding="utf-8")


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
