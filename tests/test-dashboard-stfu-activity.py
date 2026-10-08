#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Regression tests for the separate STFU log activity integration."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PATCHER_PATH = ROOT / "lib/patch_dashboard_stfu_activity.py"
HELPER = ROOT / "lib/dvswitch_mods_stfu_activity.php"
DMR_PATCHER = ROOT / "lib/patch_dashboard_dmr.py"
INSTALLER = ROOT / "mod-dashboard-stfu-activity.sh"
MANAGER = ROOT / "manage-dvswitch-mods.sh"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("FAIL: " + message)


spec = importlib.util.spec_from_file_location("stfu_activity_patcher", PATCHER_PATH)
patcher = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(patcher)

fixtures = {
    "functions": "<?php\n$lastHeard = getLastHeard($reverseLogLinesMMDVM);\n?>\n",
    "lh": (
        "<?php\n$" + "dvsModsTarget = dvsModsTargetDisplay($listElem[1], $listElem[4], $listElem[6], $listElem[0]);\n"
        + '                             if ($listElem[1] == "DMR Slot 1" && $listElem[5] == "Net")  {echo "<td colspan=\\"3\\" style=\\"background:#f93;\\">&nbsp;&nbsp;&nbsp;RX DMR&nbsp;&nbsp;&nbsp;</td>";}\n'
    ),
    "localtx": (
        "<?php\n$" + "dvsModsTarget = dvsModsTargetDisplay($listElem[1], $listElem[4], $listElem[6], $listElem[0]);\n"
        + 'if ($listElem[5] == "LNet" && ($listElem[1] == "D-Star" || startsWith($listElem[1], "DMR") || $listElem[1] == "YSF" || $listElem[1]== "P25" || $listElem[1]== "NXDN")) {\n'
        + '    echo "row";\n}\n'
    ),
    "status": (
        "<?php\n"
        + '            if ($existingCondition) { echo "existing"; }\n'
        + '            elseif ($listElem[2] && $listElem[6] == null && $abinfo[\'tlv\'][\'ambe_mode\']== "DSTAR" && getActualMode($lastHeard, $mmdvmconfigs) === \'D-Star\') {\n'
        + '                    echo "<td style=\\"background:#0b0; color:#030;\\">Listening</td>";\n}\n'
        + '$testMMDVModeYSF = getConfigItem("System Fusion Network", "Enable", $mmdvmconfigs);\n'
    ),
}
with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    files = {}
    for name, fixture in fixtures.items():
        path = base / f"{name}.php"
        path.write_text(fixture, encoding="utf-8")
        files[name] = path

    first = {
        "functions": patcher.patch_functions(files["functions"].read_text()),
        "lh": patcher.patch_lh(files["lh"].read_text()),
        "localtx": patcher.patch_localtx(files["localtx"].read_text()),
        "status": patcher.patch_status(files["status"].read_text()),
    }
    for name, text in first.items():
        files[name].write_text(text, encoding="utf-8")
    second = {
        "functions": patcher.patch_functions(files["functions"].read_text()),
        "lh": patcher.patch_lh(files["lh"].read_text()),
        "localtx": patcher.patch_localtx(files["localtx"].read_text()),
        "status": patcher.patch_status(files["status"].read_text()),
    }
    require(first == second, "STFU dashboard patch is not idempotent")
    require("dvsModsStfuMergeActivity($lastHeard)" in first["functions"], "STFU event rows are not merged into dashboard history")
    require("dvsModsStfuTargetDisplay($listElem[4])" in first["lh"], "Gateway Activity does not resolve STFU talkgroup names")
    require("RX STFU" in first["lh"], "Gateway Activity has no STFU RX indication")
    require('== "STFU"' in first["localtx"] and "dvsModsStfuTargetDisplay($listElem[4])" in first["localtx"], "Local Activity does not include STFU TX rows and targets")
    require("RX STFU" in first["status"] and "Listening STFU" in first["status"], "TRX Info has no STFU receive/listening state")
    require("dvsModsStfuRenderCard($abinfo, $lastHeard);" in first["status"], "separate STFU status card is not rendered")
    if shutil.which("php"):
        for path in files.values():
            subprocess.run(["php", "-l", str(path)], check=True, capture_output=True, text=True)
    else:
        print("SKIP: PHP syntax checks (php is unavailable in this workspace)")

log = """I: 2026-10-07 03:22:52.671 DMR, ODMR Begin Tx: src = 3213930, dst = 3100 (GROUP)
I: 2026-10-07 03:23:08.514 DMR, ODMR End Tx:DMR frame count was 264 frames
I: 2026-10-07 03:23:11.438 DMR, ODMR Begin Rx: src = 1234567, dst = 3100 (GROUP)
I: 2026-10-07 03:23:20.438 DMR, ODMR End Rx:DMR frame count was 100 frames
"""
if shutil.which("php"):
    with tempfile.TemporaryDirectory() as directory:
        log_path = Path(directory) / "STFU.log"
        log_path.write_text(log, encoding="utf-8")
        empty_log_path = Path(directory) / "STFU-empty.log"
        empty_log_path.write_text("", encoding="utf-8")
        talkgroup_path = Path(directory) / "TGList_BM.txt"
        talkgroup_path.write_text("3100;0;USA-BRIDGE;TG3100\n93;0;NORTH_AMERICA;TG93\n", encoding="utf-8")
        program = f'''<?php
function isProcessRunning($name) {{ return true; }}
require {str(HELPER)!r};
$rows = dvsModsStfuActivityRows(array({str(log_path)!r}));
echo json_encode($rows);
$rowsJson = json_encode($rows);
ob_start();
dvsModsStfuRenderCard(array('tlv' => array('ambe_mode' => 'YSF')), array(), array({str(log_path)!r}), {str(talkgroup_path)!r});
$card = ob_get_clean();
echo "\\nCARD:".$card;
'''
        result = subprocess.run(["php"], input=program, text=True, capture_output=True, check=True)
        rows_json, card_output = result.stdout.split("\nCARD:", 1)
        rows = json.loads(rows_json)
        require(len(rows) == 2, "STFU parser did not produce both RX and TX events")
        require(rows[0][1] == "STFU" and rows[0][2] == "1234567" and rows[0][5] == "LNet" and rows[0][6] == "5.9", "local STFU TX record was parsed incorrectly")
        require(rows[1][1] == "STFU" and rows[1][2] == "3213930" and rows[1][4] == "TG 3100" and rows[1][5] == "Net" and rows[1][6] == "15.6", "network STFU RX record was parsed incorrectly")
        require(all(row[7:9] == ["---", "---"] for row in rows), "STFU Loss and BER do not use the dashboard's standard unavailable marker")
        require("STFU Net" in card_output, "STFU card header is not consistent with the other mode cards")
        require('Room<br/><span style="color:#b5651d;' in card_output,
                "STFU card friendly target does not use the dashboard target color")
        require("USA-BRIDGE</span><br/><span" in card_output and "(TG 3100)" in card_output,
                "STFU card did not put the talkgroup number on a separate line")
        require("Listening</span>" not in card_output, "STFU card showed Listening despite a logged target")
        tuned_program = f'''<?php
function isProcessRunning($name) {{ return true; }}
require {str(HELPER)!r};
dvsModsStfuRenderCard(array('tlv' => array('ambe_mode' => 'STFU'), 'last_tune' => '93'), array(), array({str(log_path)!r}), {str(talkgroup_path)!r});
'''
        tuned_result = subprocess.run(["php"], input=tuned_program, text=True, capture_output=True, check=True)
        require("NORTH AMERICA</span><br/><span" in tuned_result.stdout and "(TG 93)" in tuned_result.stdout,
                "STFU card did not show the currently tuned friendly target")
        saved_target_path = Path(directory) / "stfu-target"
        saved_target_path.write_text("93\n", encoding="utf-8")
        saved_program = f'''<?php
function isProcessRunning($name) {{ return true; }}
require {str(HELPER)!r};
dvsModsStfuRenderCard(array('tlv' => array('ambe_mode' => 'DMR')), array(), array({str(empty_log_path)!r}), {str(talkgroup_path)!r}, {str(saved_target_path)!r});
'''
        saved_result = subprocess.run(["php"], input=saved_program, text=True, capture_output=True, check=True)
        require("NORTH AMERICA</span><br/><span" in saved_result.stdout and "(TG 93)" in saved_result.stdout,
                "STFU card did not show its saved target after reboot when another mode is active")
else:
    print("SKIP: STFU log parser runtime cases (php is unavailable in this workspace)")

installer_text = INSTALLER.read_text()
manager_text = MANAGER.read_text()
require("--check" in installer_text and "--install" in installer_text and "--uninstall" in installer_text, "standalone installer actions are incomplete")
require("dashboard-stfu-activity" in manager_text.split("readonly -a COMPONENTS=(", 1)[1].split(")", 1)[0], "manager does not register STFU activity")
require("dvswitch-mode-buttons" not in installer_text, "STFU activity component depends on the Mode Buttons repository")
require("/var/log/dvswitch/STFU.log" in HELPER.read_text(), "STFU parser does not use the documented node log path")
require("null, '---', '---'" in HELPER.read_text(), "STFU rows do not use the standard unavailable Loss/BER markers")
require("STFU Net</th>" in HELPER.read_text(), "STFU Net card label was regressed")
require("$liveMode === 'STFU'" in HELPER.read_text() and "$abinfo['last_tune']" in HELPER.read_text(), "STFU card does not retain the live selected target")
require("/var/lib/dvswitch-mode-buttons/stfu-target" in HELPER.read_text(), "STFU card does not read the optional saved-target snapshot")
require("STFU activity feed v6" in HELPER.read_text(), "repo-root STFU helper is not the intended v6 helper")
require("STFU activity feed v[123456]" in installer_text, "installer does not accept the v6 helper during upgrade")
require("if ($mode !== 'STFU') { return; }" not in HELPER.read_text(), "STFU card is hidden outside STFU mode")
dmr_source = DMR_PATCHER.read_text()
dmr_helper = dmr_source.split("helper = r'''", 1)[1].split("'''", 1)[0]
require("STFU" not in dmr_helper, "fresh DMR Master helper still handles STFU")
print("PASS: STFU log event mapping, dashboard integrations, standalone installer, and manager registration")
