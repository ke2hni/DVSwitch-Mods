#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Add STFU status cells to the existing dashboard Modes and Networks strip.
# This standalone installer intentionally modifies only include/system.php.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="1.0.0"
readonly TARGET="${DVS_STFU_STATUS_TARGET:-/usr/share/dvswitch/include/system.php}"
readonly BACKUP_ROOT="${DVS_STFU_STATUS_BACKUP_ROOT:-/var/backups/dvswitch-mods/dashboard-stfu-status}"

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
usage() {
    printf 'Dashboard STFU status modification %s\n' "$SCRIPT_VERSION"
    printf 'Usage: sudo %s {--check|--install|--uninstall BACKUP-NAME}\n' "$(basename "$0")"
}
require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this script with sudo."; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

run_python() {
    local action=${1:?action required} backup_name=${2:-}
    STFU_ACTION="$action" STFU_TARGET="$TARGET" STFU_BACKUP_ROOT="$BACKUP_ROOT" STFU_BACKUP_NAME="$backup_name" python3 - <<'PY_STFU_MOD'
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

action = os.environ["STFU_ACTION"]
target = Path(os.environ["STFU_TARGET"])
backup_root = Path(os.environ["STFU_BACKUP_ROOT"])
backup_name = os.environ["STFU_BACKUP_NAME"]
marker = b"// DVSwitch-Mods: STFU Modes and Networks status v1"
function_anchor = b"$rawuptime = shell_exec('cat /proc/uptime');"
mode_original = b'    <?php showMode("D-Star", $mmdvmconfigs);?>'
network_original = b'  <?php showMode("D-Star Network", $mmdvmconfigs);?></tr>'
mode_added = mode_original + b'<?php dvsModsShowSTFUStatus("STFU"); ?>'
network_added = b'  <?php showMode("D-Star Network", $mmdvmconfigs);?><?php dvsModsShowSTFUStatus("STFU Net");?></tr>'
function_signature = b"function dvsModsShowSTFUStatus($label)"


def fail(message):
    raise RuntimeError(message)


def read_target(path):
    if not path.is_file() or path.is_symlink():
        fail(f"target must be an existing regular, non-symlink file: {path}")
    return path.read_bytes()


def installed_function(data):
    newline = b"\r\n" if b"\r\n" in data else b"\n"
    lines = [
        marker,
        b"if (!function_exists('dvsModsShowSTFUStatus')) {",
        b"    function dvsModsShowSTFUStatus($label) {",
        b'        if (isProcessRunning("STFU")) {',
        b'            echo "<td style=\\"background:#12AD2A; color:#030; width:8%;\\">&nbsp;".$label."&nbsp;</td>\\n";',
        b"        } else {",
        b'            echo "<td style=\\"background:#b00; color:#f9f9f9; width:8%;\\">&nbsp;".$label."&nbsp;</td>\\n";',
        b"        }",
        b"    }",
        b"}",
    ]
    return newline.join(lines)


def inspect(data):
    function = installed_function(data)
    markers = data.count(marker)
    mode_new = data.count(mode_added)
    network_new = data.count(network_added)
    function_count = data.count(function)
    if markers == 1 and (mode_new, network_new, function_count) == (1, 1, 1):
        return "installed"
    if markers != 0 or mode_new or network_new or function_signature in data:
        fail("partial or ambiguous STFU modification found; refusing to change system.php")
    counts = (data.count(function_anchor), data.count(mode_original), data.count(network_original))
    if counts != (1, 1, 1):
        fail(f"unsupported or ambiguous system.php sections; expected one each of the three matching anchors, found {counts}")
    return "ready"


def make_candidate(data):
    if inspect(data) == "installed":
        return data
    newline = b"\r\n" if b"\r\n" in data else b"\n"
    function = installed_function(data)
    candidate = data.replace(function_anchor, function + newline + function_anchor, 1)
    candidate = candidate.replace(mode_original, mode_added, 1)
    candidate = candidate.replace(network_original, network_added, 1)
    if inspect(candidate) != "installed":
        fail("candidate verification failed")
    return candidate


def lint(path):
    result = subprocess.run(["php", "-l", str(path)], text=True, capture_output=True)
    if result.returncode:
        fail("PHP syntax validation failed: " + (result.stderr or result.stdout).strip())


def atomic_write(destination, content, metadata_from):
    info = metadata_from.stat()
    fd, raw_temp = tempfile.mkstemp(prefix=f".{destination.name}.stfu-", dir=destination.parent)
    temporary = Path(raw_temp)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.chown(temporary, info.st_uid, info.st_gid)
        os.chmod(temporary, stat.S_IMODE(info.st_mode))
        os.replace(temporary, destination)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def new_backup_directory():
    if backup_root.exists() and backup_root.is_symlink():
        fail(f"refusing symbolic-link backup directory: {backup_root}")
    backup_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(backup_root, 0o700)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    candidate = backup_root / f"install-{stamp}"
    suffix = 0
    while candidate.exists():
        suffix += 1
        candidate = backup_root / f"install-{stamp}-{suffix}"
    candidate.mkdir(mode=0o700)
    return candidate


try:
    if action in ("check", "install"):
        original = read_target(target)
        state = inspect(original)
        lint(target)
        if action == "check":
            if state == "installed":
                print("ALREADY MODIFIED: both STFU status cells are installed. No files changed.")
            else:
                candidate = make_candidate(original)
                fd, raw_temp = tempfile.mkstemp(prefix="dvswitch-stfu-check-", suffix=".php")
                with os.fdopen(fd, "wb") as output:
                    output.write(candidate)
                try:
                    lint(Path(raw_temp))
                finally:
                    Path(raw_temp).unlink(missing_ok=True)
                print("READY: exact Modes and Networks sections found; STFU cells can be installed. No files changed.")
        elif state == "installed":
            print("PASS: STFU status cells are already installed; no new backup created.")
        else:
            candidate = make_candidate(original)
            fd, raw_temp = tempfile.mkstemp(prefix="dvswitch-stfu-install-", suffix=".php", dir=target.parent)
            with os.fdopen(fd, "wb") as output:
                output.write(candidate)
            temp_path = Path(raw_temp)
            try:
                lint(temp_path)
            finally:
                temp_path.unlink(missing_ok=True)
            backup = new_backup_directory()
            shutil.copy2(target, backup / target.name)
            try:
                atomic_write(target, candidate, target)
                lint(target)
                if inspect(read_target(target)) != "installed":
                    fail("post-install verification failed")
            except Exception:
                atomic_write(target, original, backup / target.name)
                raise
            print("PASS: STFU status cells installed atomically.")
            print(f"Backup: {backup}")
    elif action == "uninstall":
        if not re.fullmatch(r"install-[0-9]{8}-[0-9]{6}(?:-[0-9]+)?", backup_name):
            fail(f"invalid backup name: {backup_name}")
        backup_dir = backup_root / backup_name
        if not backup_dir.is_dir() or backup_dir.is_symlink():
            fail(f"protected backup not found: {backup_name}")
        backup_file = backup_dir / target.name
        original = read_target(backup_file)
        lint(backup_file)
        current = read_target(target)
        if inspect(current) != "installed":
            fail("current system.php does not contain the complete STFU modification; refusing uninstall")
        lint(target)
        atomic_write(target, original, backup_file)
        lint(target)
        print(f"PASS: system.php restored from {backup_name}.")
    else:
        fail(f"unknown action: {action}")
except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
    print(f"ERROR: {exc}", file=sys.stderr)
    sys.exit(1)
PY_STFU_MOD
}

main() {
    require_root
    require_command python3
    require_command php
    case "${1:-}" in
        --check)
            [[ $# -eq 1 ]] || die "--check takes no extra arguments."
            run_python check
            ;;
        --install)
            [[ $# -eq 1 ]] || die "--install takes no extra arguments."
            run_python install
            ;;
        --uninstall|--restore)
            [[ $# -eq 2 ]] || die "--uninstall requires one backup name."
            run_python uninstall "$2"
            ;;
        --help|-h) usage ;;
        *) usage >&2; exit 2 ;;
    esac
}

main "$@"
