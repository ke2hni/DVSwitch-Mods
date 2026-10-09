#!/usr/bin/env python3
# Version: 1.0.0
# SPDX-License-Identifier: MIT

"""Tests for independent timestamped BM/TGIF Gateway Activity labels."""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PATCHER_PATH = ROOT / "lib/patch_dashboard_activity_modes.py"
HELPER = ROOT / "lib/dvswitch_mods_activity_mode.php"
WRITER = ROOT / "lib/dvswitch_mods_dmr_network_history.py"
INSTALLER = ROOT / "mod-dashboard-activity-modes.sh"
MANAGER = ROOT / "manage-dvswitch-mods.sh"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("FAIL: " + message)


spec = importlib.util.spec_from_file_location("activity_mode_patcher", PATCHER_PATH)
patcher = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(patcher)

# Test parser patching, DMR-only Gateway display and removal of the earlier
# experimental Local Activity wrapper. The code is idempotent after install.
with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    functions = base / "functions.php"
    lh = base / "lh.php"
    localtx = base / "localtx.php"
    functions.write_text("""<?php
function getHeardList($logLines) {
    $timestamp = substr($logLines, 3, 19);
    $timestamp = substr($logLines, 3, 19);
}
function getLastHeard() {}
?>
""")
    cell = patcher.ORIGINAL_CELL
    lh.write_text("<?php\ninclude_once dirname(dirname(__FILE__)).'/include/functions.php';\n" + cell + "\n?>\n")
    localtx.write_text("<?php\n" + patcher.OLD_MARKER + "\n" + patcher.INCLUDE + "\n" + patcher.OLD_BEFORE + cell + patcher.OLD_AFTER + "\n?>\n")
    patcher.patch_file(functions, patcher.patch_functions)
    patcher.patch_file(lh, patcher.patch_lh)
    patcher.patch_file(localtx, patcher.clean_localtx)
    first = (functions.read_bytes(), lh.read_bytes(), localtx.read_bytes())
    patcher.patch_file(functions, patcher.patch_functions)
    patcher.patch_file(lh, patcher.patch_lh)
    patcher.patch_file(localtx, patcher.clean_localtx)
    require(first == (functions.read_bytes(), lh.read_bytes(), localtx.read_bytes()), "patcher is not idempotent")
    require(functions.read_text().count("substr($logLines, 3, 23)") == 2, "millisecond timestamps were not retained")
    require("$listElem[5]" in lh.read_text(), "Gateway Activity patch does not pass the traffic source")
    require("dvsModsActivityModeLabel(" not in localtx.read_text(), "Local Activity still has the previous relabel wrapper")
    for path in (functions, lh, localtx):
        if shutil.which("php"):
            subprocess.run(["php", "-l", str(path)], check=True, capture_output=True, text=True)

uploaded = ROOT.parents[1] / "upload"
for filename, transform in (
    ("functions(20261006-233123).php", patcher.patch_functions),
    ("lh(20261006-233121).php", patcher.patch_lh),
    ("localtx(20261006-233121).php", patcher.clean_localtx),
):
    fixture = uploaded / filename
    if fixture.is_file():
        patched = transform(fixture.read_text(encoding="utf-8"))
        if filename.startswith("functions"):
            require(patched.count("substr($logLine, 3, 23)") == 2, "uploaded MMDVM parser fixture is unsupported")
        elif filename.startswith("lh"):
            require("$listElem[5]" in patched, "uploaded Gateway Activity fixture was not patched")
        else:
            require("dvsModsActivityModeLabel(" not in patched, "uploaded Local Activity fixture retained old wrapper")

with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    history = base / "history.tsv"
    environment = os.environ.copy()
    environment.update({
        "DVS_DMR_NETWORK_HISTORY_FILE": str(history),
        "DVS_DMR_NETWORK_HISTORY_LOCK": str(base / "lock"),
        "DVS_MMDVM_BRIDGE_INI": str(base / "MMDVM_Bridge.ini"),
    })
    def record(network: str, stamp: int) -> None:
        subprocess.run(["python3", str(WRITER), "--record", network, str(stamp)], env=environment, check=True, capture_output=True)

    record("BM", 1790805600123)
    record("BM", 1790805600123)  # duplicate hook/path event is ignored
    record("TGIF", 1790805660456)
    record("BM", 1790805720789)
    require(history.read_text() == "1790805600123\tBM\n1790805660456\tTGIF\n1790805720789\tBM\n", "writer did not keep ordered distinct network transitions")
    ini = base / "MMDVM_Bridge.ini"
    ini.write_text("[DMR Network]\nAddress=tgif.network\nPort=62030\n")
    subprocess.run(["python3", str(WRITER), "--current"], env=environment, check=True, capture_output=True, text=True)
    require(history.read_text().splitlines()[-1].endswith("\tTGIF"), "standalone INI watcher did not detect TGIF")
    subprocess.run(["python3", str(WRITER), "--seed-current"], env=environment, check=True, capture_output=True, text=True)
    require(history.read_text().splitlines()[-1].endswith("\tTGIF"), "install-time seed did not recognize current network")

with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    history = base / "history.tsv"
    history.write_text("1790805600000\tBM\n1790805600300\tTGIF\n")
    environment = os.environ.copy()
    environment.update({
        "DVS_DMR_NETWORK_HISTORY_FILE": str(history),
        "DVS_DMR_NETWORK_HISTORY_LOCK": str(base / "lock"),
    })
    subprocess.run(["python3", str(WRITER), "--record", "TGIF", "1790805600200"], env=environment, check=True, capture_output=True)
    require(history.read_text() == "1790805600000\tBM\n1790805600200\tTGIF\n", "out-of-order button/watch events were not sorted and collapsed")

with tempfile.TemporaryDirectory() as directory:
    history = Path(directory) / "history.tsv"
    history.write_text("1790805600123\tBM\n1790805660456\tTGIF\n1790805720789\tBM\n")
    labels = [
        ("DMR", "2026-09-30 22:00:00.100", "Net", "DMR"),
        ("DMR Slot 2", "2026-09-30 22:00:00.200", "Net", "BM"),
        ("DMR Slot 1", "2026-09-30 22:01:00.500", "Net", "TGIF"),
        ("DMR", "2026-09-30 22:02:00.800", "Net", "BM"),
        ("DMR Slot 2", "2026-09-30 22:01:00.500", "LNet", "DMR Slot 2"),
        ("YSF", "2026-09-30 22:01:00.500", "Net", "YSF"),
        ("DMR", "not-a-log-time", "Net", "DMR"),
    ]
    program = f'''<?php
require {str(HELPER)!r};
$cases = {json.dumps(labels)};
foreach ($cases as $case) {{
  $actual = dvsModsActivityModeLabel($case[0], $case[1], $case[2], {str(history)!r});
  if ($actual !== $case[3]) {{ fwrite(STDERR, "FAIL: ".json_encode($case)." => ".$actual."\\n"); exit(1); }}
}}
'''
    if shutil.which("php"):
        subprocess.run(["php"], input=program, text=True, capture_output=True, check=True)
    else:
        print("SKIP: PHP helper cases (php unavailable)")

installer = INSTALLER.read_text()
manager = MANAGER.read_text()
require("--check" in installer and "--install" in installer and "--restore" in installer, "installer interface is incomplete")
require("DVSwitch-Mode-Buttons current-mode state is missing" not in installer, "Mods installer depends on Mode Buttons")
require("--seed-current" in installer and "--current" in installer, "installer lacks history initialization and standalone detection")
require("dashboard-activity-modes) CHILD_SCRIPT=\"$SCRIPT_DIR/mod-dashboard-activity-modes.sh\"" in manager, "manager no longer uses the established installer filename")
require("dashboard-activity-modes" in manager.split("readonly -a COMPONENTS=(", 1)[1].split(")", 1)[0], "manager does not register the component")
print("PASS: timestamped DMR network history, Gateway-only labels, standalone install, and manager registration")
