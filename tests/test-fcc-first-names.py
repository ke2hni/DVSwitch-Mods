#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

from __future__ import annotations

import importlib.util
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "mod-dashboard-fcc-first-names.sh"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


builder = load("builder", ROOT / "lib/build_fcc_first_names.py")
patcher = load("patcher", ROOT / "lib/patch_dashboard_first_names.py")


def require(value, message):
    if not value:
        raise AssertionError(message)


def row(kind, fields, length):
    values = [""] * length
    values[0] = kind
    for index, value in fields.items():
        values[index - 1] = value
    return "|".join(values) + "\r\n"


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    archive = root / "l_amat.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as target:
        target.writestr("counts", "File Creation Date: test\n 4 /test/HD.dat\n 4 /test/EN.dat\n")
        for name in ("AM.dat", "CO.dat", "HS.dat", "LA.dat", "SC.dat", "SF.dat"):
            target.writestr(name, "")
        target.writestr(
            "HD.dat",
            row("HD", {2: "1", 5: "KE2HNI", 6: "A"}, 59)
            + row("HD", {2: "2", 5: "AA0AY", 6: "A"}, 59)
            + row("HD", {2: "3", 5: "OLD1", 6: "E"}, 59)
            + row("HD", {2: "4", 5: "W1CLB", 6: "A"}, 59),
        )
        target.writestr(
            "EN.dat",
            row("EN", {2: "1", 5: "KE2HNI", 9: "Jeff"}, 30)
            + row("EN", {2: "2", 5: "AA0AY", 9: "LAURA"}, 30)
            + row("EN", {2: "3", 5: "OLD1", 9: "Expired"}, 30)
            + row("EN", {2: "4", 5: "W1CLB", 9: ""}, 30),
        )
    output = root / "names.dat"
    require(builder.build(archive, output, 2) == 2, "wrong generated record count")
    require(builder.validate(output, 2) == 2, "generated database did not validate")
    records = output.read_bytes()
    require(len(records) == 2 * builder.RECORD_SIZE, "records are not fixed width")
    require(b"AA0AY     |Laura" in records and b"KE2HNI    |Jeff" in records, "first-name normalization failed")
    require(b"Expired" not in records and b"W1CLB" not in records, "inactive or blank-name record leaked")
    previous = output.read_bytes()
    broken = root / "broken.zip"
    broken.write_bytes(b"not a zip")
    try:
        builder.build(broken, output, 2)
    except builder.BuildError:
        pass
    else:
        raise AssertionError("invalid archive was accepted")
    require(output.read_bytes() == previous, "failed build changed the working database")


lh = '''<?php
include_once dirname(dirname(__FILE__)).'/include/functions.php';''' + "    \n" + '''?>
?>
      <th>Time (<?php echo date('T')?>)</th>
      <th>Callsign</th>
<?php
    if (DISPLAYNAME == "YES" && file_exists(DMRIDDATPATH."/DMRIds.dat") && ! empty(DMRIDDATPATH."/DMRIds.dat")) { echo "<th>Name</th>"; }
?>
                // Display NAME by DV8AWC
old stock lookup
                if (strlen($listElem[4]) == 1)
'''
localtx = '''<?php
include_once dirname(dirname(__FILE__)).'/include/functions.php';''' + "    \n" + '''?>
?>
      <th>Time (<?php echo date('T')?>)</th>
      <th>Callsign</th>
      <th>Target</th>
                    }
                        if (strlen($listElem[4]) == 1)
'''
patcher.SUPPORTED["lh.php"].add(patcher.digest(lh))
patcher.SUPPORTED["localtx.php"].add(patcher.digest(localtx))
patched_lh = patcher.patch_text(lh, "lh.php")
patched_local = patcher.patch_text(localtx, "localtx.php")
v1_lh = patched_lh.replace("width:115px", "width:140px", 1)
v1_local = patched_local.replace("width:115px", "width:140px", 1)
patcher.SUPPORTED_MODIFIED_V1["lh.php"].add(patcher.digest(v1_lh))
patcher.SUPPORTED_MODIFIED_V1["localtx.php"].add(patcher.digest(v1_local))
for value in (patched_lh, patched_local):
    require(value.count(patcher.MARKER) == 1, "marker missing")
    require(value.count(patcher.INCLUDE) == 1, "helper include missing")
    require(value.count("<th>Name</th>") == 1, "Name heading missing")
    require(value.count("dvsModsFccFirstName($listElem[2])") == 1, "lookup call missing")
    require(value.count("echo '<td align=\"left\" style=\"font-weight:bold;color:#464646;\">&nbsp;<b>'.htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, \"UTF-8\").'</b></td>';" ) == 1, "safe PHP name-cell output is missing")
require(patcher.patch_text(patched_lh, "lh.php") == patched_lh, "lh patch is not idempotent")
require(patcher.patch_text(patched_local, "localtx.php") == patched_local, "localtx patch is not idempotent")
require(patcher.patch_text(v1_lh, "lh.php") == patched_lh, "lh v1 width was not upgraded")
require(patcher.patch_text(v1_local, "localtx.php") == patched_local, "localtx v1 width was not upgraded")
try:
    patcher.patch_text(patched_lh + "<!-- altered -->\n", "lh.php")
except patcher.PatchError:
    pass
else:
    raise AssertionError("altered modified checksum was accepted")

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    for name, fixture in (("lh.php", lh), ("localtx.php", localtx)):
        path = root / name
        path.write_bytes(fixture.replace("\n", "\r\n").encode())
        patcher.patch_file(path)
        raw = path.read_bytes()
        require(raw.count(b"\r\n") == raw.count(b"\n"), f"{name} CRLF endings were not preserved")
        first = raw
        patcher.patch_file(path)
        require(path.read_bytes() == first, f"{name} CRLF patch is not idempotent")

installer = INSTALLER.read_text(encoding="utf-8")
require('readonly WORK_ROOT="/var/lib/mmdvm"' in installer, "installer work root is not on persistent storage")
require("/var/tmp/dvswitch-fcc-firstnames" not in installer and "/tmp/dvswitch-fcc-firstnames" not in installer, "installer still uses a size-limited temporary filesystem")

print("PASS: FCC first-name builder and dashboard patcher tests")
