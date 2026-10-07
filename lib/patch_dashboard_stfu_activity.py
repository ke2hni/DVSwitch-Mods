#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Add STFU log events to the existing Gateway, Local, and TRX views."""

from __future__ import annotations

import argparse
from pathlib import Path
import re

OLD_MARKER = "// DVSwitch-Mods: STFU activity feed integration v1"
MARKER = "// DVSwitch-Mods: STFU activity feed integration v2"
INCLUDE = "include_once dirname(__FILE__).'/dvswitch_mods_stfu_activity.php';"


class PatchError(RuntimeError):
    pass


def replace_once(text: str, old: str, new: str, description: str) -> str:
    count = text.count(old)
    if count != 1:
        raise PatchError(f"unsupported or ambiguous {description}: {count} matches")
    return text.replace(old, new, 1)


def patch_functions(text: str) -> str:
    if OLD_MARKER in text and MARKER not in text:
        if text.count(OLD_MARKER) != 1 or text.count(INCLUDE) != 1 or text.count("dvsModsStfuMergeActivity($lastHeard)") != 1:
            raise PatchError("partial or duplicate legacy STFU functions.php integration")
        return text.replace(OLD_MARKER, MARKER, 1)
    anchor = "$lastHeard = getLastHeard($reverseLogLinesMMDVM);"
    new = (f"{MARKER}\n{INCLUDE}\n" + anchor +
           "\n$lastHeard = dvsModsStfuMergeActivity($lastHeard);")
    if MARKER in text:
        if text.count(MARKER) != 1 or text.count(INCLUDE) != 1 or text.count("dvsModsStfuMergeActivity($lastHeard)") != 1:
            raise PatchError("partial or duplicate STFU functions.php integration")
        return text
    return replace_once(text, anchor, new, "functions.php last-heard initialization")


def patch_lh(text: str) -> str:
    if OLD_MARKER in text and MARKER not in text:
        if text.count(OLD_MARKER) != 1 or "dvsModsStfuTargetDisplay($listElem[4])" not in text or "RX STFU" not in text:
            raise PatchError("partial or duplicate legacy STFU Gateway Activity integration")
        return text.replace(OLD_MARKER, MARKER, 1)
    rx = '                             if ($listElem[1] == "DMR Slot 1" && $listElem[5] == "Net")  {echo "<td colspan=\\"3\\" style=\\"background:#f93;\\">&nbsp;&nbsp;&nbsp;RX DMR&nbsp;&nbsp;&nbsp;</td>";}\n'
    if MARKER in text:
        if text.count(MARKER) != 1 or "dvsModsStfuTargetDisplay($listElem[4])" not in text or "RX STFU" not in text:
            raise PatchError("partial or duplicate STFU Gateway Activity integration")
        return text
    text = text.replace("<?php\n", f"<?php\n{MARKER}\n", 1)
    target = "$dvsModsTarget = dvsModsTargetDisplay($listElem[1], $listElem[4], $listElem[6], $listElem[0]);"
    replacement = "$dvsModsTarget = ($listElem[1] === 'STFU') ? dvsModsStfuTargetDisplay($listElem[4]) : dvsModsTargetDisplay($listElem[1], $listElem[4], $listElem[6], $listElem[0]);"
    text = replace_once(text, target, replacement, "Gateway Activity Target helper")
    anchor = '                             if ($listElem[1] == "DMR Slot 1"'
    if text.count(anchor) != 1:
        raise PatchError("Gateway Activity DMR RX status anchor is missing or ambiguous")
    insertion = '                             if ($listElem[1] == "STFU" && $listElem[5] == "Net")  {echo "<td colspan=\\"3\\" style=\\"background:#4aa361;\\">&nbsp;&nbsp;&nbsp;RX STFU&nbsp;&nbsp;&nbsp;</td>";}\n'
    text = text.replace(anchor, insertion + anchor, 1)
    return text


def patch_localtx(text: str) -> str:
    if OLD_MARKER in text and MARKER not in text:
        if text.count(OLD_MARKER) != 1 or "dvsModsStfuTargetDisplay($listElem[4])" not in text or '== "STFU"' not in text:
            raise PatchError("partial or duplicate legacy STFU Local Activity integration")
        return text.replace(OLD_MARKER, MARKER, 1)
    if MARKER in text:
        if text.count(MARKER) != 1 or "dvsModsStfuTargetDisplay($listElem[4])" not in text or '== "STFU"' not in text:
            raise PatchError("partial or duplicate STFU Local Activity integration")
        return text
    text = text.replace("<?php\r\n", f"<?php\r\n{MARKER}\r\n", 1) if "<?php\r\n" in text else text.replace("<?php\n", f"<?php\n{MARKER}\n", 1)
    target = "$dvsModsTarget = dvsModsTargetDisplay($listElem[1], $listElem[4], $listElem[6], $listElem[0]);"
    replacement = "$dvsModsTarget = ($listElem[1] === 'STFU') ? dvsModsStfuTargetDisplay($listElem[4]) : dvsModsTargetDisplay($listElem[1], $listElem[4], $listElem[6], $listElem[0]);"
    text = replace_once(text, target, replacement, "Local Activity Target helper")
    old_filter = '$listElem[1]== "NXDN")) {'
    new_filter = '$listElem[1]== "NXDN" || $listElem[1] == "STFU")) {'
    return replace_once(text, old_filter, new_filter, "Local Activity mode filter")


def patch_status(text: str) -> str:
    if MARKER in text:
        if (text.count(MARKER) != 1 or "dvsModsStfuRenderCard($abinfo, $lastHeard);" not in text
                or "RX STFU" not in text or "Listening DMR" not in text or "Listening STFU" not in text):
            raise PatchError("partial or duplicate STFU TRX/status integration")
        return text
    trx_anchor = '            elseif ($listElem[2] && $listElem[6] == null && $abinfo[\'tlv\'][\'ambe_mode\']== "DSTAR"'
    if text.count(trx_anchor) != 1:
        raise PatchError("TRX Info receive-state insertion anchor is missing or ambiguous")
    rx_branch = '''            elseif ($listElem[2] && $listElem[6] == null && $abinfo['tlv']['ambe_mode']== "STFU" && getActualMode($lastHeard, $mmdvmconfigs) === 'STFU') {
                    echo "<td style=\\\"background:#4aa361;\\\">RX STFU</td>";
                    }
'''
    live_mode_fallbacks = '''            elseif (isset($abinfo['tlv']['ambe_mode']) && strtoupper($abinfo['tlv']['ambe_mode']) === 'DMR' && getActualMode($lastHeard, $mmdvmconfigs) !== 'DMR') {
                    echo "<td style=\\"background:#f93;\\">Listening DMR</td>";
                    }
            elseif (isset($abinfo['tlv']['ambe_mode']) && strtoupper($abinfo['tlv']['ambe_mode']) === 'STFU' && getActualMode($lastHeard, $mmdvmconfigs) !== 'STFU') {
                    echo "<td style=\\"background:#0b0; color:#030;\\">Listening STFU</td>";
                    }
'''
    if OLD_MARKER in text and MARKER not in text:
        if text.count(OLD_MARKER) != 1 or text.count(rx_branch) != 1:
            raise PatchError("legacy STFU TRX integration is incomplete or ambiguous")
        text = text.replace(rx_branch, rx_branch + live_mode_fallbacks, 1)
        return text.replace(OLD_MARKER, MARKER, 1)
    text = text.replace(trx_anchor, rx_branch + live_mode_fallbacks + trx_anchor, 1)
    listening = '                    echo "<td style=\\"background:#0b0; color:#030;\\">Listening</td>";'
    listening_replacement = '''                    if (isset($abinfo['tlv']['ambe_mode']) && strtoupper($abinfo['tlv']['ambe_mode']) === 'STFU') {
                            echo "<td style=\\"background:#0b0; color:#030;\\">Listening STFU</td>";
                    } else {
''' + listening + '''
                    }'''
    text = replace_once(text, listening, listening_replacement, "TRX idle listening label")
    card_anchor = "$testMMDVModeYSF = getConfigItem(\"System Fusion Network\", \"Enable\", $mmdvmconfigs);"
    text = replace_once(text, card_anchor, f"{MARKER}\ndvsModsStfuRenderCard($abinfo, $lastHeard);\n" + card_anchor, "STFU status card insertion")
    return text


def transform(path: Path, function) -> None:
    raw = path.read_bytes()
    if b"\r" in raw.replace(b"\r\n", b""):
        raise PatchError(f"mixed line endings are unsupported in {path}")
    newline = "\r\n" if b"\r\n" in raw else "\n"
    text = raw.decode("utf-8").replace("\r\n", "\n")
    path.write_text(function(text).replace("\n", newline), encoding="utf-8", newline="")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--functions", type=Path, required=True)
    parser.add_argument("--lh", type=Path, required=True)
    parser.add_argument("--localtx", type=Path, required=True)
    parser.add_argument("--status", type=Path, required=True)
    args = parser.parse_args()
    for path, patch in ((args.functions, patch_functions), (args.lh, patch_lh),
                        (args.localtx, patch_localtx), (args.status, patch_status)):
        transform(path, patch)


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, PatchError) as error:
        raise SystemExit(f"ERROR: {error}")
