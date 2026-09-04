#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

"""Patch supported DVSwitch activity tables for FCC first-name display."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

LEGACY_MARKER = "// DVSwitch-Mods: FCC first-name activity columns v1"
MARKER = "// DVSwitch-Mods: FCC first-name activity columns v2"
INCLUDE = "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_fcc_first_names.php';"
SUPPORTED = {
    "lh.php": {
        "f8e6c9801c2613796f070921cee442943ed2dfdd4ec2466a266a6df369a8dc70",
        "8cca963621cd9e1dd393826cb48d71df9f4fb0d6a88a578e5043bf9c5915926d",
    },
    "localtx.php": {
        "decf6b59e0eba78877381e2b3d9bdf70dbbeab4d9fdb24f3eefb62e3233453b4",
        "cd0fa845874efe221546b54055b9cb20a9631badcd9ec63f1cd544337a2f1b9e",
    },
}
SUPPORTED_MODIFIED_V1 = {
    "lh.php": {
        "464e3540d1cb8e61a6a9731840000e544bd49972b64939db3198e9d1637df343",
        "98f0347584ad7f409a6111ed1bd53beec69ba9ecd80838f0c5599cb465337b30",
    },
    "localtx.php": {
        "fab0efbc0b540d87996c886a63b0b1f68248641404d8afb5eafa7cfd9f818f6c",
        "ba27d38ed7a72cdd48516c1269c904c19ddcf7b152700cbf3941e6fd02ff2fb9",
    },
}
SUPPORTED_MODIFIED_V2 = {
    "lh.php": {
        "d3ec7d18720de2e14d20de0ea6cbbfd232acb4c33b304195242962dfd1c6b4cd",
        "ff5a497ed23e8c0fd467e69cd730d9d45a0c243d5ac54d9040a24500b4b449f0",
    },
    "localtx.php": {
        "c231c522a29aa486f37c9e8c944ce82a25b188e301fb6a7a50ae1cd2469e3d02",
        "bf39a188d3bab2ed46386a4bd716cde476c78e5db3cf818afc906c455a3d441f",
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
    text = replace_once(text, "      <th>Time (<?php echo date('T')?>)</th>", "      <th style=\"white-space:nowrap;width:115px;\">Time (<?php echo date('T')?>)</th>", "lh time header")
    old_header = '''      <th>Callsign</th>
<?php
    if (DISPLAYNAME == "YES" && file_exists(DMRIDDATPATH."/DMRIds.dat") && ! empty(DMRIDDATPATH."/DMRIds.dat")) { echo "<th>Name</th>"; }
?>'''
    text = replace_once(text, old_header, "      <th>Callsign</th>\n      <th>Name</th>", "lh stock name header")
    start_token = "// Display NAME by DV8AWC"
    end_token = "if (strlen($listElem[4]) == 1)"
    if text.count(start_token) != 1 or text.count(end_token) != 1:
        raise PatchError("unsupported or ambiguous lh stock name block")
    start = text.rfind("\n", 0, text.index(start_token)) + 1
    end = text.rfind("\n", 0, text.index(end_token)) + 1
    if start >= end:
        raise PatchError("invalid lh stock name-block order")
    replacement = '''                $dvsModsFirstName = dvsModsFccFirstName($listElem[2]);
                echo '<td align="left" style="font-weight:bold;color:#464646;">&nbsp;<b>'.htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").'</b></td>';
'''
    return text[:start] + replacement + text[end:]


def add_dmr_id_resolution(text: str, name: str) -> str:
    token = "if ((is_numeric($listElem[2]) || strpos($listElem[2], \"openSPOT\") !== FALSE)"
    if name == "localtx.php":
        token = "if (is_numeric($listElem[2]) || strpos($listElem[2], \"openSPOT\") !== FALSE)"
    if text.count(token) != 1:
        raise PatchError(f"unsupported or ambiguous {name} callsign-rendering anchor: {text.count(token)} matches")
    insertion = text.rfind("\n", 0, text.index(token)) + 1
    indent = text[insertion:text.index(token)]
    line = indent + "$listElem[2] = dvsModsDmrIdCallsign($listElem[2]);\n"
    return text[:insertion] + line + text[insertion:]


def validate_current(text: str, name: str) -> None:
    token = "$listElem[2] = dvsModsDmrIdCallsign($listElem[2]);"
    if text.count(token) != 1:
        raise PatchError(f"incomplete modified {name}")
    recovered = text.replace(MARKER, LEGACY_MARKER, 1)
    line_start = recovered.rfind("\n", 0, recovered.index(token)) + 1
    line_end = recovered.index("\n", recovered.index(token)) + 1
    recovered = recovered[:line_start] + recovered[line_end:]
    if digest(recovered) not in SUPPORTED_MODIFIED_V2[name]:
        raise PatchError(f"unsupported modified {name} hash: {digest(text)}")


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
    text = replace_once(text, "      <th>Time (<?php echo date('T')?>)</th>", "      <th style=\"white-space:nowrap;width:115px;\">Time (<?php echo date('T')?>)</th>", "localtx time header")
    text = replace_once(text, "      <th>Callsign</th>\n      <th>Target</th>", "      <th>Callsign</th>\n      <th>Name</th>\n      <th>Target</th>", "localtx name header")
    token = "if (strlen($listElem[4]) == 1)"
    if text.count(token) != 1:
        raise PatchError(f"unsupported or ambiguous localtx callsign block: {text.count(token)} matches")
    insertion = text.rfind("\n", 0, text.index(token)) + 1
    replacement = '''                        $dvsModsFirstName = dvsModsFccFirstName($listElem[2]);
                        echo '<td align="left" style="font-weight:bold;color:#464646;">&nbsp;<b>'.htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").'</b></td>';
'''
    return text[:insertion] + replacement + text[insertion:]


def patch_text(text: str, name: str) -> str:
    if text.count(LEGACY_MARKER) == 1:
        value = digest(text)
        if value in SUPPORTED_MODIFIED_V1[name]:
            if text.count("white-space:nowrap;width:140px;") != 1:
                raise PatchError(f"invalid v1 time width in {name}")
            text = text.replace("white-space:nowrap;width:140px;", "white-space:nowrap;width:115px;", 1)
        elif value not in SUPPORTED_MODIFIED_V2[name]:
            raise PatchError(f"unsupported legacy modified {name} hash: {value}")
        text = text.replace(LEGACY_MARKER, MARKER, 1)
        return add_dmr_id_resolution(text, name)
    if text.count(MARKER) == 1:
        if text.count(INCLUDE) != 1 or text.count("dvsModsFccFirstName($listElem[2])") != 1 or text.count("dvsModsDmrIdCallsign($listElem[2])") != 1 or text.count("<th>Name</th>") != 1:
            raise PatchError(f"incomplete modified {name}")
        validate_current(text, name)
        return text
    if MARKER in text or LEGACY_MARKER in text:
        raise PatchError(f"duplicate markers in {name}")
    if digest(text) not in SUPPORTED[name]:
        raise PatchError(f"unsupported unmodified {name} hash: {digest(text)}")
    result = patch_lh(text) if name == "lh.php" else patch_localtx(text)
    result = add_dmr_id_resolution(result, name)
    if result.count(MARKER) != 1:
        raise PatchError(f"failed to install marker in {name}")
    return result


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
