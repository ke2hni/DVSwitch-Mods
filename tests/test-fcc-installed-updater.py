#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(value, message):
    if not value:
        raise AssertionError(message)


def row(kind, fields, length):
    values = [""] * length
    values[0] = kind
    for index, value in fields.items():
        values[index - 1] = value
    return "|".join(values) + "\r\n"


def make_archive(path: Path, second_name: str) -> None:
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as target:
        target.writestr("counts", "File Creation Date: test\n 2 /test/HD.dat\n 2 /test/EN.dat\n")
        for name in ("AM.dat", "CO.dat", "HS.dat", "LA.dat", "SC.dat", "SF.dat"):
            target.writestr(name, "")
        target.writestr("HD.dat", row("HD", {2: "1", 5: "KE2HNI", 6: "A"}, 59) + row("HD", {2: "2", 5: "AA0AY", 6: "A"}, 59))
        target.writestr("EN.dat", row("EN", {2: "1", 9: "Jeff"}, 30) + row("EN", {2: "2", 9: second_name}, 30))


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    library = root / "lib"
    dashboard = root / "dashboard"
    state = root / "state"
    units = root / "units"
    commands = root / "commands"
    sbin = root / "sbin"
    for path in (library, dashboard, state, units, commands, sbin):
        path.mkdir()

    builder = library / "build_fcc_first_names.py"
    builder_text = (ROOT / "lib/build_fcc_first_names.py").read_text(encoding="utf-8").replace("MIN_PRODUCTION_RECORDS = 700_000", "MIN_PRODUCTION_RECORDS = 2")
    builder.write_text(builder_text, encoding="utf-8")
    transaction = library / "transaction.sh"
    shutil.copyfile(ROOT / "lib/transaction.sh", transaction)

    lh = dashboard / "lh.php"
    localtx = dashboard / "localtx.php"
    helper = dashboard / "dvswitch_mods_fcc_first_names.php"
    lh.write_text("supported test lh\n", encoding="utf-8")
    localtx.write_text("supported test localtx\n", encoding="utf-8")
    helper.write_text("supported test helper\n", encoding="utf-8")
    database = state / "dvswitch-mods-fcc-first-names.dat"
    archive = root / "fcc.zip"
    make_archive(archive, "Laura")
    subprocess.run(["python3", str(builder), "--archive", str(archive), "--output", str(database)], check=True, stdout=subprocess.DEVNULL)
    database.chmod(0o644)
    for path in (lh, localtx, helper):
        path.chmod(0o644)

    service = units / "dvswitch-fcc-first-names-update.service"
    timer = units / "dvswitch-fcc-first-names-update.timer"
    service.write_text("test service\n", encoding="utf-8")
    timer.write_text("test timer\n", encoding="utf-8")
    service.chmod(0o644); timer.chmod(0o644); builder.chmod(0o644); transaction.chmod(0o644)

    updater = sbin / "dvswitch-fcc-first-names-update"
    updater_text = (ROOT / "lib/dvswitch_fcc_first_names_update.sh").read_text(encoding="utf-8")
    replacements = {
        'readonly LIBRARY_DIR="/usr/local/lib/dvswitch-mods"': f'readonly LIBRARY_DIR="{library}"',
        'readonly UPDATER_TARGET="/usr/local/sbin/dvswitch-fcc-first-names-update"': f'readonly UPDATER_TARGET="{updater}"',
        'readonly SERVICE_TARGET="/etc/systemd/system/dvswitch-fcc-first-names-update.service"': f'readonly SERVICE_TARGET="{service}"',
        'readonly TIMER_TARGET="/etc/systemd/system/dvswitch-fcc-first-names-update.timer"': f'readonly TIMER_TARGET="{timer}"',
        'readonly LH_TARGET="/usr/share/dvswitch/include/lh.php"': f'readonly LH_TARGET="{lh}"',
        'readonly LOCALTX_TARGET="/usr/share/dvswitch/include/localtx.php"': f'readonly LOCALTX_TARGET="{localtx}"',
        'readonly HELPER_TARGET="/usr/share/dvswitch/include/dvswitch_mods_fcc_first_names.php"': f'readonly HELPER_TARGET="{helper}"',
        'readonly DATABASE_TARGET="/var/lib/mmdvm/dvswitch-mods-fcc-first-names.dat"': f'readonly DATABASE_TARGET="{database}"',
        'readonly WORK_ROOT="/var/lib/mmdvm"': f'readonly WORK_ROOT="{state}"',
        'readonly BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-fcc-first-names"': f'readonly BACKUP_ROOT="{root / "backups"}"',
        'readonly LOCK_FILE="/run/lock/dvswitch-fcc-first-names-update.lock"': f'readonly LOCK_FILE="{root / "update.lock"}"',
        'readonly BUILDER_SHA256="d4831315dfdd133174a415fe288c6c3c8d49852336a0dcc196b4b0a2130e4ae2"': f'readonly BUILDER_SHA256="{digest(builder)}"',
        'readonly TRANSACTION_SHA256="13d743d6065f88888725a1aefe98c8d4ad957974ec5cd991a52ff20ac44a6532"': f'readonly TRANSACTION_SHA256="{digest(transaction)}"',
        'readonly HELPER_SHA256="df8606e288b996c2189372d8b10a9c8e5b2ab3f935cd732589ed12a6df9fd257"': f'readonly HELPER_SHA256="{digest(helper)}"',
        '    "8bbfdd234c051354b29d94e496348ca315ecd858c67d8f335b245b0a5b7c1c13"': f'    "{digest(lh)}"',
        '    "48df64a5612d02c66d5f7da748b0b840de2f25fa60a4456b22fcd925e7e1f0fd"': f'    "{digest(localtx)}"',
        '    . /etc/os-release': '    ID=debian; VERSION_ID=12',
        'require_owner_mode "$DATABASE_TARGET" root www-data 644': 'require_owner_mode "$DATABASE_TARGET" root root 644',
    }
    for old, new in replacements.items():
        require(old in updater_text, f"updater test substitution is stale: {old}")
        updater_text = updater_text.replace(old, new) if old.startswith("require_owner_mode") else updater_text.replace(old, new, 1)
    updater.write_text(updater_text, encoding="utf-8")
    updater.chmod(0o755)

    curl = commands / "curl"
    curl.write_text('#!/bin/bash\nset -eu\nout=""\nwhile [[ $# -gt 0 ]]; do if [[ "$1" == --output ]]; then out=$2; shift 2; else shift; fi; done\ncp -- "$FCC_TEST_ARCHIVE" "$out"\n', encoding="utf-8")
    curl.chmod(0o755)
    systemctl = commands / "systemctl"
    systemctl.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
    systemctl.chmod(0o755)
    environment = os.environ.copy()
    environment["PATH"] = f"{commands}:{environment['PATH']}"
    environment["FCC_TEST_ARCHIVE"] = str(archive)

    original = digest(database)
    result = subprocess.run([str(updater)], env=environment, text=True, capture_output=True)
    require(result.returncode == 0, f"identical update failed: {result.stderr}")
    require("byte-for-byte identical" in result.stdout, "identical result was not reported")
    require(digest(database) == original, "identical update changed the database")
    require(not (root / "backups").exists(), "identical update created a backup")
    require(not list(state.glob(".dvswitch-fcc-firstnames.*")), "identical update left a workspace")

    make_archive(archive, "Laurie")
    result = subprocess.run([str(updater)], env=environment, text=True, capture_output=True)
    require(result.returncode == 0, f"changed update failed: {result.stderr}")
    require("installed atomically" in result.stdout, "changed installation was not reported")
    changed = digest(database)
    require(changed != original, "changed archive did not replace the database")
    require(len(list((root / "backups").glob("install-*"))) == 1, "changed update did not create exactly one backup")
    require(not list(state.glob(".dvswitch-fcc-firstnames.*")), "changed update left a workspace")

    archive.write_bytes(b"truncated zip")
    result = subprocess.run([str(updater)], env=environment, text=True, capture_output=True)
    require(result.returncode != 0, "broken FCC archive was accepted")
    require(digest(database) == changed, "failed update changed the installed database")
    require(len(list((root / "backups").glob("install-*"))) == 1, "failed build created a backup")
    require(not list(state.glob(".dvswitch-fcc-firstnames.*")), "failed update left a workspace")

    result = subprocess.run([str(updater), "--remove-updater"], env=environment, text=True, capture_output=True)
    require(result.returncode == 0, f"permanent removal utility failed: {result.stderr}")
    require(database.is_file() and lh.is_file() and localtx.is_file() and helper.is_file(), "updater removal deleted the working Name modification")
    require(all(not path.exists() for path in (updater, builder, transaction, service, timer)), "updater removal left installed components")

print("PASS: installed FCC updater safety tests")
