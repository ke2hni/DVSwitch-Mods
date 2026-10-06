#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Regression tests for selected-network activity labels."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import os
from datetime import datetime
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
PATCHER_PATH = ROOT / "lib/patch_dashboard_activity_modes.py"
HELPER = ROOT / "lib/dvswitch_mods_activity_mode.php"
HISTORY_RECORDER = ROOT / "lib/dvswitch_mods_activity_mode_history.py"
INSTALLER = ROOT / "mod-dashboard-activity-modes.sh"
MANAGER = ROOT / "manage-dvswitch-mods.sh"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("FAIL: " + message)


spec = importlib.util.spec_from_file_location("activity_mode_patcher", PATCHER_PATH)
patcher = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(patcher)

for filename in ("lh.php", "localtx.php"):
    for padded in (False, True):
        cell = patcher.MODE_CELL_PADDED[filename] if padded else patcher.MODE_CELL[filename]
        original = (
            "<?php\n"
            "include_once dirname(dirname(__FILE__)).'/include/functions.php';\n"
            + cell + "\n"
            "$targetMode = dvsModsTargetDisplay($listElem[1], $listElem[4], $listElem[6]);\n"
        )
        changed = patcher.patch_text(original, filename)
        require(changed.count(patcher.MARKER) == 1, filename + " marker missing")
        require(changed.count(patcher.INCLUDE) == 1, filename + " helper include missing")
        require(changed.count("dvsModsActivityModeLabel($listElem[1], $listElem[0])") == 1,
                filename + " mode wrapper missing")
        require(changed.index("$listElem[1] = $dvsModsActivityOriginalMode;") <
                changed.index("$targetMode = dvsModsTargetDisplay"),
                filename + " original mode was not restored before target formatting")
        require(patcher.patch_text(changed, filename) == changed, filename + " patch is not idempotent")

        mixed = original.replace("\n", "\r\n")
        mixed_changed = patcher.patch_text(mixed.replace("\r\n", "\n"), filename).replace("\n", "\r\n")
        require(b"\r\n" in mixed_changed.encode() and b"\n" not in mixed_changed.replace("\r\n", "").encode(),
                filename + " CRLF handling failed")

    target_include = (
        "<?php\n"
        "include_once dirname(dirname(__FILE__)).'/include/functions.php';\n"
        "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_fcc_first_names.php';\n"
        "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_target_display.php';\n"
        + patcher.MODE_CELL_PADDED[filename] + "\n"
    )
    changed = patcher.patch_text(target_include, filename)
    require(changed.count(patcher.INCLUDE) == 1, filename + " helper include duplicated")
    require(changed.index(patcher.INCLUDE) > changed.index("dvswitch_mods_target_display.php"),
            filename + " helper include was not placed after existing dashboard helpers")

with tempfile.TemporaryDirectory() as directory:
    state_tgif = Path(directory) / "current-mode-tgif"
    state_bm = Path(directory) / "current-mode-bm"
    state_stfu = Path(directory) / "current-mode-stfu"
    state_ysf = Path(directory) / "current-mode-ysf"
    event_time = "2026-09-30 22:00:00"
    system_timezone = ZoneInfo(Path("/etc/timezone").read_text().strip().lstrip("/"))
    epoch = int(datetime.strptime(event_time, "%Y-%m-%d %H:%M:%S").replace(tzinfo=system_timezone).timestamp())
    for state, mode in ((state_tgif, "TGIF"), (state_bm, "BM"), (state_stfu, "STFU"), (state_ysf, "YSF")):
        state.write_text(mode + "\n")
        os.utime(state, (epoch - 10, epoch - 10))
    no_history = Path(directory) / "no-history.tsv"
    cases = [
        ("DMR", event_time, "TGIF", str(state_tgif)),
        ("DMR Slot 2", event_time, "TGIF", str(state_tgif)),
        ("DMR Slot 1", "2026-09-30 21:59:40", "DMR Slot 1", str(state_tgif)),
        ("YSF", event_time, "YSF", str(state_tgif)),
        ("DMR Slot 3", event_time, "DMR Slot 3", str(state_tgif)),
        ("DMR", "not-a-log-time", "DMR", str(state_tgif)),
        ("DMR", event_time, "BM", str(state_bm)),
        ("DMR", event_time, "DMR", str(state_stfu)),
        ("DMR", event_time, "DMR", str(state_ysf)),
    ]

    history = Path(directory) / "activity-mode-history.tsv"
    history.write_text(f"{epoch - 40}\tTGIF\n{epoch - 30}\tBM\n{epoch - 20}\tSTFU\n{epoch - 15}\tYSF\n{epoch - 10}\tTGIF\n")
    tgif_stfu_history = Path(directory) / "tgif-stfu-history.tsv"
    tgif_stfu_history.write_text(f"{epoch - 40}\tTGIF\n{epoch - 30}\tSTFU\n{epoch - 20}\tYSF\n")
    tgif_stfu_state = Path(directory) / "tgif-stfu-current-mode"
    tgif_stfu_state.write_text("STFU\n")
    os.utime(tgif_stfu_state, (epoch - 30, epoch - 30))
    historical_cases = [
        ("DMR", "2026-09-30 21:59:20", "TGIF"),
        ("DMR Slot 2", "2026-09-30 21:59:30", "BM"),
        ("DMR Slot 1", "2026-09-30 21:59:40", "BM"),
        ("DMR Slot 2", "2026-09-30 21:59:45", "BM"),
        ("DMR", "2026-09-30 21:59:49", "BM"),
        ("DMR", event_time, "TGIF"),
        ("YSF", "2026-09-30 21:59:50", "YSF"),
    ]

    program = f'''<?php
require {str(HELPER)!r};
function dvsModsTestFail($message) {{ file_put_contents('php://stderr', $message."\\n"); exit(1); }}
$cases = {json.dumps(cases)};
foreach ($cases as $case) {{
    $actual = dvsModsActivityModeLabel($case[0], $case[1], $case[3], {str(no_history)!r});
    if ($actual !== $case[2]) {{ dvsModsTestFail("FAIL: ".json_encode($case)." => ".$actual); }}
}}
$historicalCases = {json.dumps(historical_cases)};
$history = {str(history)!r};
foreach ($historicalCases as $case) {{
    $actual = dvsModsActivityModeLabel($case[0], $case[1], {str(state_ysf)!r}, $history);
    if ($actual !== $case[2]) {{ dvsModsTestFail("FAIL: history ".json_encode($case)." => ".$actual); }}
}}
$tgifStfuHistory = {str(tgif_stfu_history)!r};
$tgifStfuState = {str(tgif_stfu_state)!r};
foreach (["2026-09-30 21:59:25", "2026-09-30 21:59:35"] as $tgifRxTime) {{
    $actual = dvsModsActivityModeLabel("DMR Slot 2", $tgifRxTime, $tgifStfuState, $tgifStfuHistory);
    if ($actual !== "TGIF") {{ dvsModsTestFail("FAIL: TGIF DMR label changed across STFU selection at ".$tgifRxTime." => ".$actual); }}
}}
$laterDmrState = {str(Path(directory) / 'later-current-mode')!r};
file_put_contents($laterDmrState, "TGIF\\n");
touch($laterDmrState, {epoch + 10});
$nonDmrRx = dvsModsActivityModeLabel("DMR Slot 2", "2026-09-30 21:59:40", $laterDmrState, $history);
if ($nonDmrRx !== "BM") {{ dvsModsTestFail("FAIL: previous BM DMR network label was lost after a non-DMR mode transition => ".$nonDmrRx); }}
$staleDmrState = {str(Path(directory) / 'stale-current-mode')!r};
file_put_contents($staleDmrState, "DSTAR\\n");
touch($staleDmrState, {epoch - 30});
$afterBootSync = dvsModsActivityModeLabel("DMR Slot 2", "2026-09-30 21:59:55", $staleDmrState, $history);
if ($afterBootSync !== "TGIF") {{ dvsModsTestFail("FAIL: boot TGIF transition did not override stale DSTAR state => ".$afterBootSync); }}
$beforeBootSync = dvsModsActivityModeLabel("DMR Slot 2", "2026-09-30 21:59:15", $staleDmrState, $history);
if ($beforeBootSync !== "DMR Slot 2") {{ dvsModsTestFail("FAIL: pre-sync row was relabeled => ".$beforeBootSync); }}
echo "PASS: selected-network activity label cases\\n";
?>'''
    php = shutil.which("php")
    if php:
        result = subprocess.run([php], input=program, text=True, capture_output=True)
        require(result.returncode == 0, result.stderr.strip() or "PHP activity-mode helper tests failed")
        print(result.stdout.strip())
    else:
        print("SKIP: PHP runtime helper cases (php unavailable)")

with tempfile.TemporaryDirectory() as directory:
    directory_path = Path(directory)
    state = directory_path / "current-mode"
    last_dmr = directory_path / "last-dmr-network"
    history = directory_path / "history.tsv"
    lock = directory_path / "history.lock"
    environment = os.environ.copy()
    environment.update({
        "DVS_ACTIVITY_MODE_STATE": str(state),
        "DVS_ACTIVITY_LAST_DMR": str(last_dmr),
        "DVS_ACTIVITY_MODE_HISTORY": str(history),
        "DVS_ACTIVITY_MODE_LOCK": str(lock),
        "DVS_ACTIVITY_ABINFO_GLOB": str(directory_path / "ABInfo_*.json"),
        "DVS_ACTIVITY_BRIDGE_INI": str(directory_path / "MMDVM_Bridge.ini"),
    })
    last_dmr.write_text("TGIF\n")
    os.utime(last_dmr, (epoch - 40, epoch - 40))
    state.write_text("YSF\n")
    os.utime(state, (epoch - 20, epoch - 20))
    subprocess.run(["python3", str(HISTORY_RECORDER)], env=environment, check=True)
    require(history.read_text() == f"{epoch - 40}\tTGIF\n{epoch - 20}\tYSF\n",
            "history recorder did not seed last DMR network and current mode")
    state.write_text("BM\n")
    os.utime(state, (epoch - 10, epoch - 10))
    subprocess.run(["python3", str(HISTORY_RECORDER)], env=environment, check=True)
    require(history.read_text().endswith(f"{epoch - 10}\tBM\n"),
            "history recorder did not record a selected DMR network transition")
    require(history.read_text().count("\n") == 3, "history recorder duplicated a seeded mode transition")

with tempfile.TemporaryDirectory() as directory:
    directory_path = Path(directory)
    state = directory_path / "current-mode"
    last_dmr = directory_path / "last-dmr-network"
    history = directory_path / "history.tsv"
    lock = directory_path / "history.lock"
    bridge_ini = directory_path / "MMDVM_Bridge.ini"
    abinfo = directory_path / "ABInfo_31001.json"
    stale_at = epoch - 60
    live_at = epoch - 20
    state.write_text("DSTAR\n")
    last_dmr.write_text("TGIF\n")
    history.write_text(f"{stale_at}\tDSTAR\n")
    bridge_ini.write_text("[DMR Network]\nAddress=tgif.network\nPort=62030\n")
    abinfo.write_text('{"tlv":{"ambe_mode":"DMR"}}')
    os.utime(state, (stale_at, stale_at))
    os.utime(abinfo, (live_at, live_at))
    environment = os.environ.copy()
    environment.update({
        "DVS_ACTIVITY_MODE_STATE": str(state),
        "DVS_ACTIVITY_LAST_DMR": str(last_dmr),
        "DVS_ACTIVITY_MODE_HISTORY": str(history),
        "DVS_ACTIVITY_MODE_LOCK": str(lock),
        "DVS_ACTIVITY_ABINFO_GLOB": str(directory_path / "ABInfo_*.json"),
        "DVS_ACTIVITY_BRIDGE_INI": str(bridge_ini),
    })
    subprocess.run(["python3", str(HISTORY_RECORDER)], env=environment, check=True)
    rows = [line.split("\t") for line in history.read_text().splitlines()]
    require(rows[-1][1] == "TGIF" and int(rows[-1][0]) > stale_at,
            "fresh DMR/TGIF runtime state did not supersede stale DSTAR boot state")
    require(state.read_text() == "DSTAR\n", "history startup sync unexpectedly changed Buttons-owned current-mode state")
    initial_row_count = len(rows)
    subprocess.run(["python3", str(HISTORY_RECORDER)], env=environment, check=True)
    require(len(history.read_text().splitlines()) == initial_row_count,
            "repeated boot/path capture appended a duplicate unchanged mode")

    # A live non-DMR mode remains authoritative when its ABInfo is newer.
    state.write_text("TGIF\n")
    os.utime(state, (live_at - 10, live_at - 10))
    abinfo.write_text('{"tlv":{"ambe_mode":"DSTAR"}}')
    os.utime(abinfo, (live_at + 10, live_at + 10))
    subprocess.run(["python3", str(HISTORY_RECORDER)], env=environment, check=True)
    require(history.read_text().splitlines()[-1].endswith("\tDSTAR"),
            "fresh non-DMR ABInfo mode was not recorded")

with tempfile.TemporaryDirectory() as directory:
    directory_path = Path(directory)
    history = directory_path / "history.tsv"
    bridge_ini = directory_path / "MMDVM_Bridge.ini"
    abinfo = directory_path / "ABInfo_31001.json"
    bridge_ini.write_text("[DMR Network]\nAddress=tgif.network\nPort=62030\n")
    abinfo.write_text('{"tlv":{"ambe_mode":"DMR"}}')
    os.utime(abinfo, (epoch, epoch))
    environment = os.environ.copy()
    environment.update({
        "DVS_ACTIVITY_MODE_STATE": str(directory_path / "missing-buttons-current-mode"),
        "DVS_ACTIVITY_LAST_DMR": str(directory_path / "missing-buttons-last-dmr"),
        "DVS_ACTIVITY_MODE_HISTORY": str(history),
        "DVS_ACTIVITY_MODE_LOCK": str(directory_path / "history.lock"),
        "DVS_ACTIVITY_ABINFO_GLOB": str(directory_path / "ABInfo_*.json"),
        "DVS_ACTIVITY_BRIDGE_INI": str(bridge_ini),
    })
    subprocess.run(["python3", str(HISTORY_RECORDER)], env=environment, check=True)
    require(history.read_text().endswith("\tTGIF\n"),
            "standalone activity-mode recorder requires Buttons-owned state")

with tempfile.TemporaryDirectory() as directory:
    directory_path = Path(directory)
    history = directory_path / "history.tsv"
    environment = os.environ.copy()
    environment.update({
        "DVS_ACTIVITY_MODE_STATE": str(directory_path / "missing-current-mode"),
        "DVS_ACTIVITY_LAST_DMR": str(directory_path / "missing-last-dmr"),
        "DVS_ACTIVITY_MODE_HISTORY": str(history),
        "DVS_ACTIVITY_MODE_LOCK": str(directory_path / "history.lock"),
        "DVS_ACTIVITY_ABINFO_GLOB": str(directory_path / "missing-ABInfo_*.json"),
        "DVS_ACTIVITY_BRIDGE_INI": str(directory_path / "missing-MMDVM_Bridge.ini"),
    })
    subprocess.run(["python3", str(HISTORY_RECORDER)], env=environment, check=True)
    require(history.is_file() and history.read_text() == "",
            "recorder did not initialize empty standalone history before live state exists")

installer = INSTALLER.read_text()
manager = MANAGER.read_text()
require("--check" in installer and "--install" in installer and "--restore" in installer,
        "standalone installer check/install/restore interface missing")
require("DVSwitch-Mode-Buttons current-mode state is missing" not in installer,
        "activity-mode installer still requires the separate Mode Buttons component")
require("dvswitch-mods-activity-mode-history.path" in installer and "activity-mode-history.tsv" in installer,
        "installer does not install and initialize persistent transition tracking")
require("systemctl reset-failed dvswitch-mods-activity-mode-history.path dvswitch-mods-activity-mode-history.service" in installer,
        "installer does not clear the prior systemd start-limit state before enabling the repaired tracker")
require("systemctl enable dvswitch-mods-activity-mode-history.service" in installer,
        "installer does not enable the single boot reconciliation service")
path_unit = (ROOT / "systemd/dvswitch-mods-activity-mode-history.path").read_text()
service_unit = (ROOT / "systemd/dvswitch-mods-activity-mode-history.service").read_text()
require("PathExists=" not in path_unit and "PathChanged=/opt/MMDVM_Bridge/MMDVM_Bridge.ini" in path_unit,
        "mode-history watcher must include the standalone DVSwitch bridge configuration")
require("After=local-fs.target analog_bridge.service mmdvm_bridge.service" in service_unit,
        "boot history reconciliation is not ordered after live bridge state is available")
require("WantedBy=multi-user.target" in service_unit,
        "mode-history service is not enabled for a single ordered boot reconciliation")
require("dashboard-activity-modes) CHILD_SCRIPT=\"$SCRIPT_DIR/mod-dashboard-activity-modes.sh\"" in manager,
        "manager does not register the standalone activity-label installer")
require("dashboard-activity-modes" in manager.split("readonly -a COMPONENTS=(", 1)[1].split(")", 1)[0],
        "activity-label component is absent from standard manager installation")
component_order = manager.split("readonly -a COMPONENTS=(", 1)[1].split(")", 1)[0].split()
require(component_order.index("dashboard-activity-modes") == component_order.index("dashboard-cell-padding") + 1,
        "activity-label component must follow dashboard cell padding in manager order")

print("PASS: dashboard activity-mode patcher and manager tests")
