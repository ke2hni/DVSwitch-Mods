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

ROOT = Path(__file__).resolve().parents[1]
PATCHER_PATH = ROOT / "lib/patch_dashboard_activity_modes.py"
HELPER = ROOT / "lib/dvswitch_mods_activity_mode.php"
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
    state = Path(directory) / "current-mode"
    event_time = "2026-09-30 22:00:00"
    epoch = 1790805600  # 2026-09-30 22:00:00 UTC
    cases = []
    state.write_text("TGIF\n")
    os.utime(state, (epoch - 10, epoch - 10))
    cases.extend([
        ("DMR", event_time, "TGIF"),
        ("DMR Slot 2", event_time, "TGIF"),
        ("DMR Slot 1", "2026-09-30 21:59:59", "DMR Slot 1"),
        ("YSF", event_time, "YSF"),
        ("DMR Slot 3", event_time, "DMR Slot 3"),
        ("DMR", "not-a-log-time", "DMR"),
    ])
    state.write_text("BM\n")
    os.utime(state, (epoch - 10, epoch - 10))
    cases.append(("DMR", event_time, "BM"))
    state.write_text("STFU\n")
    os.utime(state, (epoch - 10, epoch - 10))
    cases.append(("DMR", event_time, "STFU"))
    state.write_text("YSF\n")
    os.utime(state, (epoch - 10, epoch - 10))
    cases.append(("DMR", event_time, "DMR"))

    program = f'''<?php
require {str(HELPER)!r};
$cases = {json.dumps(cases)};
$state = {str(state)!r};
foreach ($cases as $case) {{
    $actual = dvsModsActivityModeLabel($case[0], $case[1], $state);
    if ($actual !== $case[2]) {{ fwrite(STDERR, "FAIL: ".json_encode($case)." => ".$actual."\\n"); exit(1); }}
}}
echo "PASS: selected-network activity label cases\\n";
?>'''
    php = shutil.which("php")
    if php:
        result = subprocess.run([php], input=program, text=True, capture_output=True)
        require(result.returncode == 0, result.stderr.strip() or "PHP activity-mode helper tests failed")
        print(result.stdout.strip())
    else:
        print("SKIP: PHP runtime helper cases (php unavailable)")

installer = INSTALLER.read_text()
manager = MANAGER.read_text()
require("--check" in installer and "--install" in installer and "--restore" in installer,
        "standalone installer check/install/restore interface missing")
require("dashboard-activity-modes) CHILD_SCRIPT=\"$SCRIPT_DIR/mod-dashboard-activity-modes.sh\"" in manager,
        "manager does not register the standalone activity-label installer")
require("dashboard-activity-modes" in manager.split("readonly -a COMPONENTS=(", 1)[1].split(")", 1)[0],
        "activity-label component is absent from standard manager installation")
component_order = manager.split("readonly -a COMPONENTS=(", 1)[1].split(")", 1)[0].split()
require(component_order.index("dashboard-activity-modes") == component_order.index("dashboard-cell-padding") + 1,
        "activity-label component must follow dashboard cell padding in manager order")

print("PASS: dashboard activity-mode patcher and manager tests")
