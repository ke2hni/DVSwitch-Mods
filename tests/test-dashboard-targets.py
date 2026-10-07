#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PATCHER_PATH = ROOT / "lib/patch_dashboard_targets.py"
HELPER = ROOT / "lib/dvswitch_mods_target_display.php"
INSTALLER = ROOT / "mod-dashboard-targets.sh"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("FAIL: " + message)


spec = importlib.util.spec_from_file_location("target_patcher", PATCHER_PATH)
patcher = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(patcher)

lh = r'''<?php
// DVSwitch-Mods: FCC first-name activity columns v2
include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_fcc_first_names.php';
\t\tif (strlen($listElem[4]) == 1) { $listElem[4] = str_pad($listElem[4], 8, " ", STR_PAD_LEFT); }
\t\tif ( substr($listElem[4], 0, 6) === 'CQCQCQ' ) {
\t\t\techo "<td align=\"left\">&nbsp;<span style=\"color:#b5651d;font-weight:bold;\">$listElem[4]</span></td>";
\t\t} else {
\t\t\techo "<td align=\"left\">&nbsp;<span style=\"color:#b5651d;font-weight:bold;\">".str_replace(" ","&nbsp;", $listElem[4])."</span></td>";
\t\t}
'''.replace("\\t", "\t")
localtx = r'''<?php
// DVSwitch-Mods: FCC first-name activity columns v2
include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_fcc_first_names.php';
\t\t\tif (strlen($listElem[4]) == 1) { $listElem[4] = str_pad($listElem[4], 8, " ", STR_PAD_LEFT); }
\t\t\techo"<td align=\"left\">&nbsp;<span style=\"color:#b5651d;font-weight:bold;\">".str_replace(" ","&nbsp;", $listElem[4])."</span></td>";
</div>
<br>
'''.replace("\\t", "\t")
for name, original in (("lh.php", lh), ("localtx.php", localtx)):
    changed = patcher.patch_text(original, name)
    require(changed.count(patcher.MARKER) == 1, name + " marker missing")
    require(changed.count("dvsModsTargetDisplay(") == 1, name + " helper call missing")
    require(changed.count(patcher.LEGEND) == (1 if name == "localtx.php" else 0), name + " legend count incorrect")
    if name == "localtx.php":
        require('margin:3px 0 0 14px;' in patcher.LEGEND, "Local Activity legend 14px alignment is missing")
    require(patcher.patch_text(changed, name) == changed, name + " patch not idempotent")
    current_target = patcher.block(name)[1]
    padded_target = patcher.cell_padding_block(name)
    for target_cell in (current_target, padded_target):
        base = changed.replace(patcher.block(name)[1], target_cell, 1)
        wrapped_target = patcher.stfu_target_block(target_cell)
        wrapped = base.replace(target_cell, wrapped_target, 1)
        require(patcher.patch_text(wrapped, name) == wrapped,
                name + " does not recognize the independent STFU target wrapper")
        legacy_wrapper = wrapped_target.replace(", $listElem[0]);", ");")
        legacy = base.replace(target_cell, legacy_wrapper, 1)
        require(patcher.patch_text(legacy, name) == wrapped,
                name + " did not upgrade the older STFU target helper call safely")
    legacy = changed.replace(patcher.MARKER, patcher.LEGACY_MARKER, 1)
    require(patcher.patch_text(legacy, name) == changed, name + " v1 upgrade failed")
    if name == "localtx.php":
        old_legend = changed.replace(patcher.LEGEND, patcher.LEGACY_LEGENDS[0], 1)
        require(patcher.patch_text(old_legend, name) == changed, name + " legacy legend upgrade failed")
        stale_legend = changed.replace(patcher.LEGEND, patcher.LEGACY_LEGENDS[-1], 1)
        require(patcher.patch_text(stale_legend, name) == changed, name + " previous short legend upgrade failed")
    altered = changed + "<!-- user customization -->\n"
    require(patcher.patch_text(altered, name) == altered, name + " user customization was not preserved")

with tempfile.TemporaryDirectory() as directory:
    data = Path(directory)
    (data / "P25Hosts.json").write_text('{"reflectors":[{"designator":10200,"name":"P25 North America","sponsor":"DVSwitch"},{"designator":43389,"name":null,"sponsor":"Lookout Mountain Amateur Radio Community"}]}')
    (data / "NXDNHosts.json").write_text('{"reflectors":[{"designator":65000,"name":"World Wide","sponsor":"Place holder"}]}')
    (data / "TGList_BM.txt").write_text("9;0;Local;TG9\n3100;0;USA_Bridge;TG3100\n999;0;BM Name;TG999\n")
    (data / "TGList_TGIF.txt").write_text("43389;0;SouthEast Link;TG43389\n999;0;Different Name;TG999\n")
    (data / "YSFHosts.txt").write_text("02034;XX-Alabama Link;host.example;42000\n44444;America-Link;host.example;42000\n")
    (data / "ircDDBGateway-2026-10-02.log").write_text(
        "M: 2026-10-02 04:07:21: Linking KE2HNI Z at startup to REF030 C\n"
        "M: 2026-10-02 04:07:22: D-Plus link to REF030 C established\n"
        "M: 2026-10-02 18:00:00: Linking KE2HNI Z to REF090 B\n"
        "M: 2026-10-02 18:00:03: D-Plus link to REF090 B established\n"
        "M: 2026-10-02 18:03:00: Remote control user has linked \"KE2HNI Z\" to \"U       \" with reconnect 4\n"
        "M: 2026-10-02 18:03:01: Removing outgoing D-Plus link KE2HNI Z, REF090 B\n"
        "M: 2026-10-02 19:37:46: Linking KE2HNI Z at startup to REF030 C\n"
        "M: 2026-10-02 19:37:47: D-Plus link to REF030 C established\n"
        "M: 2026-10-02 22:26:48: Linking KE2HNI Z at startup to REF030 C\n"
        "M: 2026-10-02 22:26:48: D-Plus link to REF030 C established\n"
    )
    cases = [
        ("P25", "TG 10200", "", "P25 North America (TG 10200)"),
        ("P25", "TG 43389", "", "Lookout Mountain Amateur Radio Community (TG 43389)"),
        ("NXDN", "TG 65000", "", "World Wide (TG 65000)"),
        ("DMR Slot 2", "TG 3100", "", "USA Bridge (TG 3100)"),
        ("DMR", "TG 43389", "", "SouthEast Link (TG 43389)"),
        ("DMR", "TG 999", "", "TG 999"),
        ("YSF", "ALL at KU0S", "98.7", "ALL at KU0S"),
        ("YSF", "*****BE6w0 at N5YX", "15.1", "*****BE6w0 at N5YX"),
        ("YSF", "ALL at N8IQT", "GPS", "ALL at N8IQT"),
        ("YSF", "America-Link 44444", "", "America-Link (TG 44444)"),
        ("D-Star", "CQCQCQ via REF058 C", "7.0", "REF058 C"),
        ("D-Star", "CQCQCQ   via REF030 C", "7.0", "REF030 C"),
        ("D-Star", "REF030 C", "7.0", "REF030 C"),
        ("D-Star", "CQCQCQ", "1.0", "General Call"),
        ("P25", "private 123", "", "private 123"),
    ]
    php_cases = json.dumps(cases)
    program = f'''<?php
    $dvsModsTargetDataDirectory = {str(directory)!r};
date_default_timezone_set("America/New_York");
$dvsModsTargetIrcDdbLogDirectory = {str(directory)!r};
require {str(HELPER)!r};
$cases = {php_cases};
foreach ($cases as $case) {{
    $actual = dvsModsTargetDisplay($case[0], $case[1], $case[2]);
    if ($actual !== $case[3]) {{ file_put_contents("php://stderr", "FAIL: ".$case[0]." / ".$case[1]." => ".$actual." expected ".$case[3]."\\n"); exit(1); }}
}}
$dstarHistoryCases = [
    ["2026-10-02 18:01:00", "REF090 B"],
    ["2026-10-02 17:42:01", "REF030 C"],
    ["2026-10-02 18:04:00", "General Call"],
    ["2026-10-02 23:57:28", "REF030 C"],
    ["2026-10-03 00:06:07", "REF030 C"],
];
foreach ($dstarHistoryCases as $case) {{
    $actual = dvsModsTargetDisplay("D-Star", "CQCQCQ", "", $case[0]);
    if ($actual !== $case[1]) {{ file_put_contents("php://stderr", "FAIL: D-Star event-time history at ".$case[0]." => ".$actual." expected ".$case[1]."\\n"); exit(1); }}
}}
echo "PASS: Target display helper cases\\n";
?>'''
    php = shutil.which("php")
    if php is None:
        helper_text = HELPER.read_text()
        for token in ("dvsModsTargetDisplay", "dvsModsTargetJsonName", "dvsModsTargetDmrNames", "dvsModsTargetYsfName", "General Call"):
            require(token in helper_text, "helper structure missing " + token)
        print("SKIP: PHP helper runtime cases (php unavailable)")
    else:
        result = subprocess.run([php], input=program, text=True, capture_output=True)
        require(result.returncode == 0, result.stderr.strip() or "PHP helper test failed")
        print(result.stdout.strip())

print("PASS: Target dashboard patcher tests")

installer = INSTALLER.read_text()
require('if ! cmp -s "$WORK_DIR/lh.php" "$LH_TARGET"; then' in installer, "installer rewrites unchanged lh.php")
require('if ! cmp -s "$WORK_DIR/localtx.php" "$LOCALTX_TARGET"; then' in installer, "installer rewrites unchanged localtx.php")
require('elif ! cmp -s "$HELPER_SOURCE" "$HELPER_TARGET"; then' in installer, "installer rewrites unchanged helper")
print("PASS: Target installer changed-components-only structure")
