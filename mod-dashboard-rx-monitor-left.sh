#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Move the existing RX Monitor button into the left status column above Status.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="1.0.0"
readonly TARGET="${DVS_RX_MONITOR_TARGET:-/usr/share/dvswitch/index.php}"
readonly BACKUP_ROOT="${DVS_RX_MONITOR_BACKUP_ROOT:-/var/backups/dvswitch-mods/dashboard-rx-monitor-left}"

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
usage() {
    printf 'Dashboard RX Monitor position modification %s\n' "$SCRIPT_VERSION"
    printf 'Usage: sudo %s {--check|--install|--uninstall BACKUP-NAME}\n' "$(basename "$0")"
}
require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this script with sudo."; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

run_python() {
    local action=${1:?action required} backup_name=${2:-}
    RX_ACTION="$action" RX_TARGET="$TARGET" RX_BACKUP_ROOT="$BACKUP_ROOT" RX_BACKUP_NAME="$backup_name" python3 - <<'PY_RX_MOD'
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

action = os.environ["RX_ACTION"]
target = Path(os.environ["RX_TARGET"])
backup_root = Path(os.environ["RX_BACKUP_ROOT"])
backup_name = os.environ["RX_BACKUP_NAME"]
marker = b"// DVSwitch-Mods: RX Monitor left of status v1"
cell_anchor = b"    echo '<td width=\"200px\" valign=\"top\" class=\"hide\" style=\"border:none;background-color:#fafafa;\">';"
nav_anchor = b"    echo '<div class=\"nav\">'.\"\\n\";"
button_echo = b'''    echo '<button class="button link" onclick="playAudioToggle(8080, this)"><b>&nbsp;&nbsp;&nbsp;<img src=images/speaker.png alt="" style="vertical-align:middle">&nbsp;&nbsp;RX Monitor&nbsp;&nbsp;&nbsp;</b></button>';'''
original_button_echo = button_echo[4:]


def fail(message):
    raise RuntimeError(message)


def read_file(path):
    if not path.is_file() or path.is_symlink():
        fail(f"target must be an existing regular, non-symlink file: {path}")
    return path.read_bytes()


def original_block(data):
    nl = b"\r\n" if b"\r\n" in data else b"\n"
    lines = [
        b'<div style="margin-top:8px;">',
        b"<?php",
        b'if ( RXMONITOR == "YES" ) {',
        b"echo '<button class=\"button link\" onclick=\"playAudioToggle(8080, this)\"><b>&nbsp;&nbsp;&nbsp;<img src=images/speaker.png alt=\"\" style=\"vertical-align:middle\">&nbsp;&nbsp;RX Monitor&nbsp;&nbsp;&nbsp;</b></button>';}",
        b"?>",
        b"</div>",
    ]
    return nl.join(lines)


def moved_block(data):
    nl = b"\r\n" if b"\r\n" in data else b"\n"
    lines = [
        b"    " + marker,
        b"    echo '<div style=\"margin-top:8px;text-align:center;\">';",
        b'    if ( RXMONITOR == "YES" ) {',
        button_echo,
        b"    }",
        b"    echo '</div>';",
    ]
    return nl.join(lines)


def inspect(data):
    old = original_block(data)
    moved = moved_block(data)
    old_count = data.count(old)
    moved_count = data.count(moved)
    markers = data.count(marker)
    if old_count == 0 and moved_count == 1 and markers == 1:
        nav_pos = data.find(nav_anchor)
        moved_pos = data.find(moved)
        if nav_pos < 0 or moved_pos > nav_pos:
            fail("RX Monitor block is not positioned before the left-column navigation")
        return "installed"
    if old_count == 1 and moved_count == 0 and markers == 0:
        if data.count(cell_anchor) != 1 or data.count(nav_anchor) != 1:
            fail("unsupported or ambiguous left status-column insertion point")
        if data.count(original_button_echo) != 1:
            fail("RX Monitor button code was not found exactly once")
        return "ready"
    if old_count == 0 and moved_count == 0 and markers == 0:
        fail("exact RX Monitor block was not found; file may be customized or use a different dashboard version")
    fail(f"partial or ambiguous RX Monitor modification (original={old_count}, moved={moved_count}, marker={markers})")


def candidate(data):
    state = inspect(data)
    if state == "installed":
        return data
    old = original_block(data)
    moved = moved_block(data)
    changed = data.replace(old, b"", 1)
    anchor = cell_anchor + (b"\r\n" if b"\r\n" in data else b"\n")
    if changed.count(anchor) != 1:
        fail("left status-column anchor changed while preparing candidate")
    changed = changed.replace(anchor, anchor + moved + (b"\r\n" if b"\r\n" in data else b"\n"), 1)
    if inspect(changed) != "installed":
        fail("candidate verification failed")
    return changed


def lint_path(path):
    result = subprocess.run(["php", "-l", str(path)], text=True, capture_output=True)
    if result.returncode:
        fail("PHP syntax validation failed: " + (result.stderr or result.stdout).strip())


def lint_bytes(content, prefix):
    fd, raw_path = tempfile.mkstemp(prefix=prefix, suffix=".php", dir=target.parent)
    temporary = Path(raw_path)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(content)
        lint_path(temporary)
    finally:
        temporary.unlink(missing_ok=True)


def atomic_write(content, metadata_from):
    info = metadata_from.stat()
    fd, raw_path = tempfile.mkstemp(prefix=f".{target.name}.rx-monitor-", dir=target.parent)
    temporary = Path(raw_path)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chown(temporary, info.st_uid, info.st_gid)
        os.chmod(temporary, stat.S_IMODE(info.st_mode))
        os.replace(temporary, target)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def create_backup():
    if backup_root.exists() and backup_root.is_symlink():
        fail(f"refusing symbolic-link backup directory: {backup_root}")
    backup_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(backup_root, 0o700)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    name = f"install-{stamp}"
    suffix = 0
    while (backup_root / name).exists():
        suffix += 1
        name = f"install-{stamp}-{suffix}"
    directory = backup_root / name
    directory.mkdir(mode=0o700)
    shutil.copy2(target, directory / target.name)
    return name, directory


try:
    if action in ("check", "install"):
        source = read_file(target)
        state = inspect(source)
        lint_path(target)
        if action == "check":
            if state == "installed":
                print("ALREADY MODIFIED: RX Monitor is positioned above Status in the left column. No files changed.")
            else:
                lint_bytes(candidate(source), "dvswitch-rx-monitor-check-")
                print("READY: exact RX Monitor block and left status column found. No files changed.")
        elif state == "installed":
            print("PASS: RX Monitor is already positioned in the left status column; no backup created.")
        else:
            updated = candidate(source)
            lint_bytes(updated, "dvswitch-rx-monitor-install-")
            backup_name, backup_dir = create_backup()
            try:
                atomic_write(updated, target)
                lint_path(target)
                if inspect(read_file(target)) != "installed":
                    fail("post-install verification failed")
            except Exception:
                atomic_write(source, backup_dir / target.name)
                raise
            print("PASS: RX Monitor moved above Status in the left column; button behavior is unchanged.")
            print(f"Backup: {backup_dir}")
    elif action == "uninstall":
        if not re.fullmatch(r"install-[0-9]{8}-[0-9]{6}(?:-[0-9]+)?", backup_name):
            fail(f"invalid backup name: {backup_name}")
        backup_dir = backup_root / backup_name
        if not backup_dir.is_dir() or backup_dir.is_symlink():
            fail(f"protected backup not found: {backup_name}")
        saved = read_file(backup_dir / target.name)
        if inspect(saved) != "ready":
            fail("backup does not contain the original RX Monitor position")
        current = read_file(target)
        if inspect(current) != "installed":
            fail("current index.php does not contain the complete RX Monitor move; refusing uninstall")
        lint_path(target)
        nl = b"\r\n" if b"\r\n" in current else b"\n"
        restore_at = b"</center>" + nl + b"</div>" + nl + b"<?php" + nl + b"function getMMDVMConfigFileContent()"
        if current.count(restore_at) != 1:
            fail("original RX Monitor insertion point is no longer unique; refusing uninstall")
        updated = current.replace(moved_block(current) + nl, b"", 1)
        updated = updated.replace(restore_at, original_block(current) + restore_at, 1)
        if inspect(updated) != "ready":
            fail("uninstall candidate verification failed")
        lint_bytes(updated, "dvswitch-rx-monitor-uninstall-")
        atomic_write(updated, target)
        lint_path(target)
        print(f"PASS: RX Monitor returned to its original centered position using {backup_name}.")
    else:
        fail(f"unknown action: {action}")
except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
    print(f"ERROR: {exc}", file=sys.stderr)
    sys.exit(1)
PY_RX_MOD
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
