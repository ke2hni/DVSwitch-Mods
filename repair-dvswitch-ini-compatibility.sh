#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Repair settings in DVSwitch-related INI files only when incompatibility with
# the exact installed binary has been proven. The currently supported repair
# removes P25Gateway's obsolete InactivityTimeout setting and makes the exact
# compiled hang-time defaults explicit without changing user-selected values.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="0.1.0-dev"
readonly TARGET="/opt/P25Gateway/P25Gateway.ini"
readonly BINARY="/opt/P25Gateway/P25Gateway"
readonly SERVICE="p25gateway.service"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/ini-compatibility"
readonly SUPPORTED_BINARY_HASH="51b1b2ed197d6be35c425a87e35b84fcbf765a4151739b2afd1523bb29334e7b"
readonly SUPPORTED_BINARY_SIZE="1427320"
readonly SUPPORTED_BUILD_ID="66fa98eb06b2d048ed7060ac138eef7b4f9514b2"
readonly SUPPORTED_PACKAGE_VERSION="20240701-32"
readonly SUPPORTED_ARCHITECTURE="arm64"

WORK_DIR=""
LIVE_TEMP=""
ACTIVE_BACKUP=""
INSTALL_ACTIVE=0

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
usage() { printf 'DVSwitch INI compatibility repair %s\nUsage: sudo %s {--check|--install|--restore BACKUP-NAME}\n' "$SCRIPT_VERSION" "$(basename "$0")"; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
require_regular_file() { [[ -f "$1" && ! -L "$1" ]] || die "Required regular non-symlink file not found: $1"; }
file_hash() { sha256sum "$1" | awk '{print $1}'; }

cleanup() {
    if [[ -n "$LIVE_TEMP" && -f "$LIVE_TEMP" ]]; then rm -f -- "$LIVE_TEMP"; fi
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" && "$WORK_DIR" == /tmp/dvswitch-ini-compatibility.* ]]; then rm -rf -- "$WORK_DIR"; fi
}

on_error() {
    local line=$1 status=$2
    trap - ERR
    set +e
    printf 'ERROR: failed near line %s (status %s).\n' "$line" "$status" >&2
    if [[ $INSTALL_ACTIVE -eq 1 && -n "$ACTIVE_BACKUP" ]]; then
        if restore_file_from "$ACTIVE_BACKUP/P25Gateway.ini" && restart_and_check; then
            printf 'Automatic rollback completed.\n' >&2
        else
            printf 'ERROR: automatic rollback failed; use protected backup %s.\n' "$ACTIVE_BACKUP" >&2
        fi
    fi
    cleanup
    exit "$status"
}
trap 'on_error $LINENO $?' ERR
trap cleanup EXIT

check_platform() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this repair with sudo."
    [[ -r /etc/os-release ]] || die "/etc/os-release is unavailable."
    . /etc/os-release
    [[ ${ID:-} == debian ]] || die "Unsupported OS: ${ID:-unknown}"
    case "${VERSION_ID:-}" in 12|13) ;; *) die "Unsupported Debian version: ${VERSION_ID:-unknown}" ;; esac
    [[ "$(dpkg --print-architecture)" == "$SUPPORTED_ARCHITECTURE" ]] || die "Unsupported system architecture: $(dpkg --print-architecture)"
}

check_exact_binary() {
    local package_record build_id
    require_regular_file "$BINARY"
    [[ "$(stat -c '%s' "$BINARY")" == "$SUPPORTED_BINARY_SIZE" ]] || die "Unsupported P25Gateway binary size: $(stat -c '%s' "$BINARY")"
    [[ "$(file_hash "$BINARY")" == "$SUPPORTED_BINARY_HASH" ]] || die "Unsupported P25Gateway binary hash: $(file_hash "$BINARY")"
    build_id=$(readelf -n "$BINARY" | awk '/Build ID:/ {print $3; exit}')
    [[ "$build_id" == "$SUPPORTED_BUILD_ID" ]] || die "Unsupported P25Gateway Build ID: ${build_id:-missing}"
    package_record=$(dpkg-query -W -f='${Version}|${Architecture}|${db:Status-Status}' p25gateway 2>/dev/null) || die "The p25gateway package is not installed."
    [[ "$package_record" == "$SUPPORTED_PACKAGE_VERSION|$SUPPORTED_ARCHITECTURE|installed" ]] || die "Unsupported p25gateway package: $package_record"
    dpkg-query -S "$TARGET" 2>/dev/null | grep -q '^p25gateway:' || die "P25Gateway.ini is not owned by the expected package."
}

preflight() {
    check_platform
    for command in awk bash chmod chown cmp cp curl date dpkg dpkg-query file grep install mktemp mv python3 readelf rm sha256sum sleep stat systemctl; do require_command "$command"; done
    check_exact_binary
    require_regular_file "$TARGET"
    [[ $(stat -c '%a' "$TARGET") =~ ^[0-7]{3,4}$ ]] || die "Unable to read target permissions."
    systemctl cat "$SERVICE" >/dev/null 2>&1 || die "Required service is unavailable: $SERVICE"
}

patch_or_validate_candidate() {
    local mode=$1 candidate=$2
    INI_MODE="$mode" INI_FILE="$candidate" python3 - <<'PY_INI'
from pathlib import Path
import os
import re
import sys

path = Path(os.environ["INI_FILE"])
mode = os.environ["INI_MODE"]

allowed = {
    "general": {"callsign", "rptaddress", "rptport", "localport", "debug", "daemon"},
    "id lookup": {"name", "time"},
    "voice": {"enabled", "language", "directory"},
    "log": {"displaylevel", "filelevel", "filepath", "fileroot", "filerotate"},
    "network": {"port", "hostsfile1", "hostsfile2", "reloadtime", "parrotaddress", "parrotport", "p252dmraddress", "p252dmrport", "static", "rfhangtime", "nethangtime", "inactivitytimeout", "debug"},
    "remote commands": {"enable", "port"},
}
required = {
    "general": {"callsign", "rptaddress", "rptport", "localport", "daemon"},
    "id lookup": {"name", "time"},
    "voice": {"enabled", "language", "directory"},
    "log": {"displaylevel", "filelevel", "filepath", "fileroot"},
    "network": {"port", "hostsfile1", "hostsfile2", "reloadtime", "parrotaddress", "parrotport", "p252dmraddress", "p252dmrport", "debug"},
    "remote commands": {"enable", "port"},
}

try:
    raw = path.read_bytes()
    if b"\x00" in raw:
        raise ValueError("NUL byte found")
    text = raw.decode("utf-8")
except Exception as exc:
    print(f"ERROR: cannot read P25Gateway.ini safely: {exc}", file=sys.stderr)
    sys.exit(1)

newline = "\r\n" if b"\r\n" in raw and raw.count(b"\r\n") >= raw.count(b"\n") else "\n"
had_final_newline = text.endswith(("\n", "\r"))
lines = text.splitlines()
section = None
sections = {}
assignments = []

for number, line in enumerate(lines, 1):
    stripped = line.strip()
    if not stripped or stripped.startswith(("#", ";")):
        continue
    match = re.fullmatch(r"\[([^\]]+)\]\s*", stripped)
    if match:
        section = " ".join(match.group(1).split()).lower()
        if section not in allowed:
            raise SystemExit(f"ERROR: unsupported section on line {number}: {match.group(1)}")
        if section in sections:
            raise SystemExit(f"ERROR: duplicate section on line {number}: {match.group(1)}")
        sections[section] = number
        continue
    match = re.match(r"^\s*([^=]+?)\s*=", line)
    if not match:
        raise SystemExit(f"ERROR: malformed active line {number}: {line}")
    if section is None:
        raise SystemExit(f"ERROR: setting outside a section on line {number}")
    key = match.group(1).strip().lower()
    if key not in allowed[section]:
        raise SystemExit(f"ERROR: unsupported or misplaced setting on line {number}: [{section}] {match.group(1).strip()}")
    assignments.append((number - 1, section, key, line))

if set(sections) != set(allowed):
    missing = sorted(set(allowed) - set(sections))
    raise SystemExit("ERROR: missing required section(s): " + ", ".join(missing))

seen = {}
for index, sec, key, line in assignments:
    identity = (sec, key)
    if identity in seen:
        raise SystemExit(f"ERROR: duplicate active setting: [{sec}] {key}")
    seen[identity] = index

for sec, keys in required.items():
    missing = sorted(key for key in keys if (sec, key) not in seen)
    if missing:
        raise SystemExit(f"ERROR: [{sec}] missing required setting(s): " + ", ".join(missing))

def value_for(sec, key):
    line = lines[seen[(sec, key)]]
    value = line.split("=", 1)[1].split("#", 1)[0].split(";", 1)[0].strip()
    return value

for key in ("port", "parrotport", "p252dmrport"):
    value = value_for("network", key)
    if not value.isdigit() or not 1 <= int(value) <= 65535:
        raise SystemExit(f"ERROR: invalid [Network] {key} value")
remote_port = value_for("remote commands", "port")
if not remote_port.isdigit() or not 1 <= int(remote_port) <= 65535:
    raise SystemExit("ERROR: invalid [Remote Commands] Port value")
for key in ("rfhangtime", "nethangtime"):
    if ("network", key) in seen:
        value = value_for("network", key)
        if not value.isdigit() or int(value) > 86400:
            raise SystemExit(f"ERROR: invalid [Network] {key} value")
if ("network", "static") in seen:
    value = value_for("network", "static")
    if not re.fullmatch(r"[0-9]+(?:\s*,\s*[0-9]+)*", value):
        raise SystemExit("ERROR: invalid [Network] Static value")

obsolete = ("network", "inactivitytimeout") in seen
if mode == "validate-source":
    sys.exit(0)
if mode == "validate-installed":
    if obsolete:
        raise SystemExit("ERROR: unsupported [Network] InactivityTimeout remains active")
    sys.exit(0)
if mode != "patch":
    raise SystemExit("ERROR: internal validation mode is invalid")
if not obsolete:
    sys.exit(0)

obsolete_index = seen[("network", "inactivitytimeout")]
indent = re.match(r"^\s*", lines[obsolete_index]).group(0)
replacement = []
if ("network", "rfhangtime") not in seen:
    replacement.append(f"{indent}RFHangTime=120")
if ("network", "nethangtime") not in seen:
    replacement.append(f"{indent}NetHangTime=60")
lines[obsolete_index:obsolete_index + 1] = replacement
output = newline.join(lines)
if had_final_newline:
    output += newline
path.write_text(output, encoding="utf-8", newline="")
PY_INI
}

prepare_candidate() {
    WORK_DIR=$(mktemp -d /tmp/dvswitch-ini-compatibility.XXXXXX)
    cp --preserve=all -- "$TARGET" "$WORK_DIR/P25Gateway.ini"
    patch_or_validate_candidate patch "$WORK_DIR/P25Gateway.ini"
    patch_or_validate_candidate validate-installed "$WORK_DIR/P25Gateway.ini"
    local first_hash
    first_hash=$(file_hash "$WORK_DIR/P25Gateway.ini")
    patch_or_validate_candidate patch "$WORK_DIR/P25Gateway.ini"
    [[ "$first_hash" == "$(file_hash "$WORK_DIR/P25Gateway.ini")" ]] || die "Embedded INI repair is not idempotent."
}

begin_backup() {
    local timestamp candidate counter=0
    install -d -o root -g root -m 0700 "$BACKUP_ROOT"
    timestamp=$(date +%Y%m%d-%H%M%S)
    candidate="$BACKUP_ROOT/install-$timestamp"
    while [[ -e "$candidate" ]]; do counter=$((counter + 1)); candidate="$BACKUP_ROOT/install-$timestamp-$counter"; done
    install -d -o root -g root -m 0700 "$candidate"
    cp -a -- "$TARGET" "$candidate/P25Gateway.ini"
    (cd "$candidate" && sha256sum P25Gateway.ini > P25Gateway.ini.sha256)
    {
        printf 'binary_sha256=%s\n' "$(file_hash "$BINARY")"
        printf 'binary_size=%s\n' "$(stat -c '%s' "$BINARY")"
        printf 'binary_build_id=%s\n' "$SUPPORTED_BUILD_ID"
        printf 'package_version=%s\n' "$SUPPORTED_PACKAGE_VERSION"
        printf 'architecture=%s\n' "$SUPPORTED_ARCHITECTURE"
        printf 'target_metadata=%s\n' "$(stat -c '%U:%G:%a' "$TARGET")"
    } > "$candidate/manifest.txt"
    chmod 0600 "$candidate/P25Gateway.ini.sha256" "$candidate/manifest.txt"
    ACTIVE_BACKUP="$candidate"
}

atomic_replace_from() {
    local source=$1
    LIVE_TEMP=$(mktemp --tmpdir="$(dirname "$TARGET")" .dvswitch-ini-compatibility.XXXXXX)
    cp --preserve=all -- "$source" "$LIVE_TEMP"
    chown --reference="$TARGET" "$LIVE_TEMP"
    chmod --reference="$TARGET" "$LIVE_TEMP"
    mv -fT -- "$LIVE_TEMP" "$TARGET"
    LIVE_TEMP=""
}

restore_file_from() {
    local source=$1
    require_regular_file "$source"
    atomic_replace_from "$source"
}

restart_and_check() {
    local code attempt
    systemctl restart "$SERVICE" || return 1
    for attempt in 1 2 3 4 5; do
        systemctl is-active --quiet "$SERVICE" && break
        sleep 1
    done
    systemctl is-active --quiet "$SERVICE" || return 1
    systemctl is-active --quiet mmdvm_bridge.service || return 1
    systemctl is-active --quiet analog_bridge.service || return 1
    code=$(curl -ksS -o /dev/null -w '%{http_code}' https://127.0.0.1/dvswitch/) || return 1
    [[ "$code" == 200 ]] || return 1
    systemctl --failed --no-legend --plain --no-pager | grep -q ' failed ' && return 1
    return 0
}

verify_installed() {
    cmp -s "$WORK_DIR/P25Gateway.ini" "$TARGET" || { printf 'ERROR: installed INI does not match the validated candidate.\n' >&2; return 1; }
    patch_or_validate_candidate validate-installed "$TARGET" || return 1
    restart_and_check || { printf 'ERROR: service or dashboard health validation failed.\n' >&2; return 1; }
}

run_check() {
    preflight
    prepare_candidate
    if cmp -s "$TARGET" "$WORK_DIR/P25Gateway.ini"; then
        patch_or_validate_candidate validate-installed "$TARGET"
        printf 'ALREADY REPAIRED: P25Gateway INI is compatible with the installed binary.\n'
    else
        printf 'REPAIR READY: %s\nBefore: %s\nAfter:  %s\n' "$TARGET" "$(file_hash "$TARGET")" "$(file_hash "$WORK_DIR/P25Gateway.ini")"
        printf 'Planned correction: remove unsupported [Network] InactivityTimeout and add only missing compiled-default hang settings.\n'
    fi
    printf 'PASS: exact P25Gateway binary, package, architecture, and INI structure are supported. No files changed.\n'
}

run_install() {
    preflight
    prepare_candidate
    if cmp -s "$TARGET" "$WORK_DIR/P25Gateway.ini"; then
        patch_or_validate_candidate validate-installed "$TARGET"
        printf 'PASS: DVSwitch INI compatibility repair is already installed.\n'
        return
    fi
    begin_backup
    INSTALL_ACTIVE=1
    atomic_replace_from "$WORK_DIR/P25Gateway.ini"
    if ! verify_installed; then
        if restore_file_from "$ACTIVE_BACKUP/P25Gateway.ini" && restart_and_check; then
            INSTALL_ACTIVE=0
            die "Installation validation failed; automatic rollback completed."
        fi
        die "Installation validation failed and automatic rollback failed; use the protected backup."
    fi
    INSTALL_ACTIVE=0
    printf 'PASS: DVSwitch INI compatibility repair installed atomically.\nBackup: %s\n' "$ACTIVE_BACKUP"
}

run_restore() {
    local name=$1 directory current
    preflight
    WORK_DIR=$(mktemp -d /tmp/dvswitch-ini-compatibility.XXXXXX)
    [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $name"
    directory="$BACKUP_ROOT/$name"
    [[ -d "$directory" && ! -L "$directory" ]] || die "Protected backup not found: $name"
    require_regular_file "$directory/P25Gateway.ini"
    require_regular_file "$directory/P25Gateway.ini.sha256"
    (cd "$directory" && sha256sum -c P25Gateway.ini.sha256 >/dev/null) || die "Protected backup checksum validation failed."
    patch_or_validate_candidate validate-source "$directory/P25Gateway.ini"
    current="$WORK_DIR/current-P25Gateway.ini"
    cp --preserve=all -- "$TARGET" "$current"
    INSTALL_ACTIVE=1
    ACTIVE_BACKUP="$WORK_DIR/restore-rollback"
    install -d -m 0700 "$ACTIVE_BACKUP"
    cp --preserve=all -- "$current" "$ACTIVE_BACKUP/P25Gateway.ini"
    restore_file_from "$directory/P25Gateway.ini"
    if ! restart_and_check; then
        restore_file_from "$current"
        restart_and_check || die "Restoration failed and the pre-restore configuration could not be recovered cleanly."
        INSTALL_ACTIVE=0
        die "Restoration health validation failed; the pre-restore configuration was recovered."
    fi
    INSTALL_ACTIVE=0
    printf 'PASS: P25Gateway.ini restored from %s.\n' "$name"
}

main() {
    case "${1:-}" in
        --check) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_check ;;
        --install) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_install ;;
        --restore) [[ $# -eq 2 ]] || die "--restore requires one backup name."; run_restore "$2" ;;
        --help|-h) usage ;;
        "") usage; exit 2 ;;
        *) die "Unknown option: $1" ;;
    esac
}
main "$@"
