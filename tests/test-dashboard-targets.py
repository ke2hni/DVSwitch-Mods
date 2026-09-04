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


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("FAIL: " + message)


spec = importlib.util.spec_from_file_location("target_patcher", PATCHER_PATH)
patcher = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(patcher)

lh = '''<?php
// DVSwitch-Mods: FCC first-name activity columns v2
include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_fcc_first_names.php';
          if (strlen($listElem[4]) == 1) { $listElem[4] = str_pad($listElem[4], 8, " ", STR_PAD_LEFT); }
          if ( substr($listElem[4], 0, 6) === 'CQCQCQ' ) {
                  echo "<td align=\"left\">&nbsp;<span style=\"color:#b5651d;font-weight:bold;\">$listElem[4]</span></td>";
          } else {
                  echo "<td align=\"left\">&nbsp;<span style=\"color:#b5651d;font-weight:bold;\">".str_replace(" ","&nbsp;", $listElem[4])."</span></td>";
          }
'''
localtx = '''<?php
// DVSwitch-Mods: FCC first-name activity columns v2
include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_fcc_first_names.php';
                     if (strlen($listElem[4]) == 1) { $listElem[4] = str_pad($listElem[4], 8, " ", STR_PAD_LEFT); }
                     echo"<td align=\"left\">&nbsp;<span style=\"color:#b5651d;font-weight:bold;\">".str_replace(" ","&nbsp;", $listElem[4])."</span></td>";
'''
patcher.SUPPORTED["lh.php"].add(patcher.digest(lh))
patcher.SUPPORTED["localtx.php"].add(patcher.digest(localtx))
for name, original in (("lh.php", lh), ("localtx.php", localtx)):
    changed = patcher.patch_text(original, name)
    require(changed.count(patcher.MARKER) == 1, name + " marker missing")
    require(changed.count("dvsModsTargetDisplay(") == 1, name + " helper call missing")
    require(patcher.patch_text(changed, name) == changed, name + " patch not idempotent")
    try:
        patcher.patch_text(changed + "<!-- altered -->\n", name)
    except patcher.PatchError:
        pass
    else:
        raise SystemExit("FAIL: altered " + name + " accepted")

with tempfile.TemporaryDirectory() as directory:
    data = Path(directory)
    (data / "P25Hosts.json").write_text('{"reflectors":[{"designator":10200,"name":"P25 North America","sponsor":"DVSwitch"},{"designator":43389,"name":null,"sponsor":"Lookout Mountain Amateur Radio Community"}]}')
    (data / "NXDNHosts.json").write_text('{"reflectors":[{"designator":65000,"name":"World Wide","sponsor":"Place holder"}]}')
    (data / "TGList_BM.txt").write_text("9;0;Local;TG9\n3100;0;USA_Bridge;TG3100\n999;0;BM Name;TG999\n")
    (data / "TGList_TGIF.txt").write_text("43389;0;SouthEast Link;TG43389\n999;0;Different Name;TG999\n")
    cases = [
        ("P25", "TG 10200", "", "P25 North America (TG 10200)"),
        ("P25", "TG 43389", "", "Lookout Mountain Amateur Radio Community (TG 43389)"),
        ("NXDN", "TG 65000", "", "World Wide (TG 65000)"),
        ("DMR Slot 2", "TG 3100", "", "USA Bridge (TG 3100)"),
        ("DMR", "TG 43389", "", "SouthEast Link (TG 43389)"),
        ("DMR", "TG 999", "", "TG 999"),
        ("YSF", "ALL at KU0S", "98.7", "Group Call"),
        ("YSF", "*****BE6w0 at N5YX", "15.1", "GPS/Data"),
        ("YSF", "ALL at N8IQT", "GPS", "GPS/Data"),
        ("D-Star", "CQCQCQ via REF058 C", "7.0", "REF058 C"),
        ("D-Star", "CQCQCQ", "1.0", "Direct"),
        ("P25", "private 123", "", "private 123"),
    ]
    php_cases = json.dumps(cases)
    program = f'''<?php
$dvsModsTargetDataDirectory = {str(directory)!r};
require {str(HELPER)!r};
$cases = {php_cases};
foreach ($cases as $case) {{
    $actual = dvsModsTargetDisplay($case[0], $case[1], $case[2]);
    if ($actual !== $case[3]) {{ file_put_contents("php://stderr", "FAIL: ".$case[0]." / ".$case[1]." => ".$actual." expected ".$case[3]."\\n"); exit(1); }}
}}
echo "PASS: Target display helper cases\\n";
?>'''
    php = shutil.which("php")
    if php is None:
        helper_text = HELPER.read_text()
        for token in ("dvsModsTargetDisplay", "dvsModsTargetJsonName", "dvsModsTargetDmrNames", "GPS/Data", "Group Call", "Direct"):
            require(token in helper_text, "helper structure missing " + token)
        print("SKIP: PHP helper runtime cases (php unavailable)")
    else:
        result = subprocess.run([php], input=program, text=True, capture_output=True)
        require(result.returncode == 0, result.stderr.strip() or "PHP helper test failed")
        print(result.stdout.strip())

print("PASS: Target dashboard patcher tests")
