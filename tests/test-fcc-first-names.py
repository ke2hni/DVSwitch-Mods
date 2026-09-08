#!/usr/bin/env python3
"""Regression tests for surgical FCC Gateway Activity patching."""
from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("patcher", ROOT / "lib/patch_dashboard_first_names.py")
patcher = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(patcher)

def require(value: bool, message: str) -> None:
    if not value:
        raise SystemExit("FAIL: " + message)

fixture = '''<?php
include_once dirname(dirname(__FILE__)).'/include/functions.php';FUNCTIONS_ANCHOR
      <th>Time (<?php echo date('T')?>)</th>
      <th>Callsign</th>
<?php
    if (DISPLAYNAME == "YES" && file_exists(DMRIDDATPATH."/DMRIds.dat") && ! empty(DMRIDDATPATH."/DMRIds.dat")) { echo "<th>Name</th>"; }
?>
        if ((is_numeric($listElem[2]) || strpos($listElem[2], "openSPOT") !== FALSE) && (strlen($listElem[2])==7)) {
// Display NAME by DV8AWC
        if ( DISPLAYNAME == "YES" ) {
        }
        if (strlen($listElem[4]) == 1) { $listElem[4] = str_pad($listElem[4], 8, " ", STR_PAD_LEFT); }
'''.replace("FUNCTIONS_ANCHOR", "    ")

changed = patcher.patch_text(fixture)
require(changed.count(patcher.MARKER) == 1, "marker missing")
require(changed.count(patcher.INCLUDE) == 1, "helper include missing")
require(changed.count("dvsModsFccFirstName($listElem[2])") == 1, "FCC lookup missing")
require(changed.count("dvsModsDmrIdCallsign($listElem[2])") == 1, "DMR resolver missing")
require("width:640px" not in changed, "fixture unexpectedly contained layout width")
require(patcher.patch_text(changed) == changed, "patch is not idempotent")

legacy = changed.replace(patcher.MARKER, patcher.LEGACY_MARKER, 1)
require(patcher.patch_text(legacy) == changed, "legacy marker was not upgraded")

targeted = changed.replace(
    "if (strlen($listElem[4]) == 1)",
    "$dvsModsTarget = dvsModsTargetDisplay($listElem[1], $listElem[4], $listElem[6]);\n\t\techo 'target';\n        if (strlen($listElem[4]) == 1)",
    1,
)
require(patcher.patch_text(targeted) == targeted, "FCC altered Target-installed Gateway Activity")

try:
    patcher.patch_text(fixture.replace("// Display NAME by DV8AWC", "// Display NAME by DV8AWC\n// Display NAME by DV8AWC"))
except patcher.PatchError:
    pass
else:
    raise SystemExit("FAIL: ambiguous FCC name block accepted")

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "lh.php"
    path.write_bytes(fixture.replace("\n", "\r\n").encode())
    patcher.patch_file(path)
    raw = path.read_bytes()
    require(b"\r\n" in raw and b"\n" not in raw.replace(b"\r\n", b""), "CRLF was not preserved")

installer = (ROOT / "mod-dashboard-fcc-first-names.sh").read_text()
require("--localtx" not in installer, "FCC installer still invokes Local Activity patching")
require('require_file "$LH_TARGET"' in installer, "FCC installer does not require Gateway Activity")
require("LOCALTX_TARGET" not in installer, "FCC installer still owns Local Activity")
print("PASS: surgical FCC Gateway Activity patcher tests")
