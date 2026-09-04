#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

from __future__ import annotations

import importlib.util
import hashlib
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "mod-dashboard-fcc-first-names.sh"
UPDATER = ROOT / "lib/dvswitch_fcc_first_names_update.sh"
SERVICE = ROOT / "systemd/dvswitch-fcc-first-names-update.service"
TIMER = ROOT / "systemd/dvswitch-fcc-first-names-update.timer"
README = ROOT / "README.md"


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
                if ((is_numeric($listElem[2]) || strpos($listElem[2], "openSPOT") !== FALSE) && (strlen($listElem[2])==7)) {
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
                        if (is_numeric($listElem[2]) || strpos($listElem[2], "openSPOT") !== FALSE) {
                        if (strlen($listElem[4]) == 1)
'''
patcher.SUPPORTED["lh.php"].add(patcher.digest(lh))
patcher.SUPPORTED["localtx.php"].add(patcher.digest(localtx))
patched_lh = patcher.patch_text(lh, "lh.php")
patched_local = patcher.patch_text(localtx, "localtx.php")
def remove_resolver(value):
    token = "$listElem[2] = dvsModsDmrIdCallsign($listElem[2]);"
    start = value.rfind("\n", 0, value.index(token)) + 1
    end = value.index("\n", value.index(token)) + 1
    return value[:start] + value[end:]


legacy_lh = remove_resolver(patched_lh.replace(patcher.MARKER, patcher.LEGACY_MARKER, 1))
legacy_local = remove_resolver(patched_local.replace(patcher.MARKER, patcher.LEGACY_MARKER, 1))
v1_lh = legacy_lh.replace("width:115px", "width:140px", 1)
v1_local = legacy_local.replace("width:115px", "width:140px", 1)
patcher.SUPPORTED_MODIFIED_V1["lh.php"].add(patcher.digest(v1_lh))
patcher.SUPPORTED_MODIFIED_V1["localtx.php"].add(patcher.digest(v1_local))
patcher.SUPPORTED_MODIFIED_V2["lh.php"].add(patcher.digest(legacy_lh))
patcher.SUPPORTED_MODIFIED_V2["localtx.php"].add(patcher.digest(legacy_local))
for value in (patched_lh, patched_local):
    require(value.count(patcher.MARKER) == 1, "marker missing")
    require(value.count(patcher.INCLUDE) == 1, "helper include missing")
    require(value.count("<th>Name</th>") == 1, "Name heading missing")
    require(value.count("dvsModsFccFirstName($listElem[2])") == 1, "lookup call missing")
    require(value.count("dvsModsDmrIdCallsign($listElem[2])") == 1, "DMR ID resolver call missing")
    require(value.count("echo '<td align=\"left\" style=\"font-weight:bold;color:#464646;\">&nbsp;<b>'.htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, \"UTF-8\").'</b></td>';" ) == 1, "safe PHP name-cell output is missing")
require(patcher.patch_text(patched_lh, "lh.php") == patched_lh, "lh patch is not idempotent")
require(patcher.patch_text(patched_local, "localtx.php") == patched_local, "localtx patch is not idempotent")
require(patcher.patch_text(v1_lh, "lh.php") == patched_lh, "lh legacy version was not upgraded")
require(patcher.patch_text(v1_local, "localtx.php") == patched_local, "localtx legacy version was not upgraded")
for name in ("lh.php", "localtx.php"):
    original_target, modified_target = patcher.target_blocks(name)
    targeted = patcher.TARGET_MARKER + "\n" + patcher.TARGET_INCLUDE + "\n" + modified_target
    expected = original_target
    if name == "localtx.php":
        targeted += patcher.TARGET_LEGEND
    require(patcher.without_target_modification(targeted, name) == expected, f"{name} Target compatibility reversal failed")
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
require("--remove-updater" in installer, "installer lacks the updater removal utility")
require("--uninstall" in installer and "uninstall_backup_file" in installer, "installer lacks protected full uninstallation")
require('"$WORK_DIR/original/lh.php"' in installer and '"$WORK_DIR/original/localtx.php"' in installer, "uninstaller does not preserve patcher-recognized dashboard basenames")
require('systemctl enable --now "$TIMER_UNIT"' in installer, "installer does not enable the weekly timer")
require('verify_updater_components' in installer, "installer does not validate permanent updater files")
require('readonly PREVIOUS_TIMER_SHA256_V110="5624772150bd1d71f231417b23cd0e48eccd624591523e7f1c0ef9ffae1dea99"' in installer, "known v1.1.0 timer upgrade checksum is missing")
require('readonly PREVIOUS_TIMER_SHA256_V112="5d929156ef445c6e3d0c7ee32609f8c2e9cf29042c4cd13b161cae7215f76974"' in installer, "known v1.1.2 timer upgrade checksum is missing")
require('supported previous release detected; --install will upgrade it' in installer, "supported release upgrade is not reported")
require('"$PREVIOUS_UPDATER_SHA256_V113"' in installer and 'rm -f -- "$PATCHER_TARGET"' in installer, "historical restore does not remove the later patcher component")
require('stage_updater_component' in installer and 'cmp -s "$source" "$target"' in installer, "unchanged updater components are not skipped during upgrade")
require('[[ "$target" != "$TIMER_TARGET" ]] || TIMER_CHANGED=1' in installer, "timer changes are not tracked")
require('SYSTEMD_CHANGED=0' in installer and 'if [[ $SYSTEMD_CHANGED -eq 1 ]]; then systemctl daemon-reload; fi' in installer, "unchanged systemd units still trigger daemon-reload")
require('if [[ $TIMER_CHANGED -eq 1 ]]' in installer and 'systemctl restart "$TIMER_UNIT"' in installer, "changed timer is not restarted")
require('elif ! systemctl is-enabled --quiet "$TIMER_UNIT" || ! systemctl is-active --quiet "$TIMER_UNIT"' in installer, "unchanged healthy timer is not left untouched")

updater = UPDATER.read_text(encoding="utf-8")
builder_checksum = hashlib.sha256((ROOT / "lib/build_fcc_first_names.py").read_bytes()).hexdigest()
transaction_checksum = hashlib.sha256((ROOT / "lib/transaction.sh").read_bytes()).hexdigest()
require(f'readonly BUILDER_SHA256="{builder_checksum}"' in updater, "permanent updater builder checksum is stale")
require(f'readonly TRANSACTION_SHA256="{transaction_checksum}"' in updater, "permanent updater transaction checksum is stale")
for value in (
    'readonly WORK_ROOT="/var/lib/mmdvm"',
    'verify_installed_modification',
    'flock -n 9',
    'curl --fail --location',
    'dvsm_backup_file "$DATABASE_TARGET"',
    'dvsm_install_candidate "$candidate" "$DATABASE_TARGET"',
    'cmp -s "$candidate" "$DATABASE_TARGET"',
    'trap cleanup EXIT',
    '--remove-updater) run_remove_updater',
):
    require(value in updater, f"permanent updater safety requirement missing: {value}")
require("/tmp/dvswitch-fcc-firstnames" not in updater and "/var/tmp/dvswitch-fcc-firstnames" not in updater, "permanent updater uses a size-limited temporary filesystem")
require("--force-update" not in updater, "unapproved force-update option was added")

service = SERVICE.read_text(encoding="utf-8")
require("ExecStart=/usr/local/sbin/dvswitch-fcc-first-names-update" in service, "service depends on the repository checkout")
require("ReadWritePaths=/var/lib/mmdvm /var/backups/dvswitch-mods /run/lock" in service, "service write access is not narrowly limited")
timer = TIMER.read_text(encoding="utf-8")
require("OnCalendar=Mon *-*-* 00:00:00" in timer, "weekly timer schedule changed unexpectedly")
require("Persistent=true" in timer and "RandomizedDelaySec=96h" in timer, "timer resilience settings are missing")
require("FixedRandomDelay" not in timer, "timer still derives a fixed delay from machine identity")

readme = README.read_text(encoding="utf-8")
for component in (INSTALLER, UPDATER, ROOT / "lib/build_fcc_first_names.py", ROOT / "lib/transaction.sh", SERVICE, TIMER, ROOT / "lib/dvswitch_mods_fcc_first_names.php"):
    require(hashlib.sha256(component.read_bytes()).hexdigest() in readme, f"README checksum is stale or missing: {component.relative_to(ROOT)}")

print("PASS: FCC first-name builder and dashboard patcher tests")
