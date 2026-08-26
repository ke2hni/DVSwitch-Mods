#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Add validated P25 and NXDN JSON downloads to the completed Stage 2
# DVSwitch updater. This is an optional modification, not a repair.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="0.1.0-dev"
readonly TARGET="/opt/MMDVM_Bridge/dvswitch.sh"
readonly DATA_DIR="/var/lib/mmdvm"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/p25-nxdn-json"
readonly STAGE2_HASH="64c2a18d5d1b236c8416bc039307bd78198fb5877a74c1949e326cffa2f836a9"
readonly MOD_MARKER="# DVSwitch-Mods: P25/NXDN JSON updater modification"

WORK_DIR=""
ACTIVE_BACKUP=""
INSTALL_ACTIVE=0

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
usage() { printf 'P25/NXDN JSON updater modification %s\nUsage: sudo %s {--check|--install|--restore BACKUP-NAME}\n' "$SCRIPT_VERSION" "$(basename "$0")"; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }

require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
require_regular_file() { [[ -f "$1" && ! -L "$1" ]] || die "Required regular non-symlink file not found: $1"; }

check_platform() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this modification with sudo."
    [[ -r /etc/os-release ]] || die "/etc/os-release is unavailable."
    . /etc/os-release
    [[ ${ID:-} == debian ]] || die "Unsupported OS: ${ID:-unknown}"
    case "${VERSION_ID:-}" in 12|13) ;; *) die "Unsupported Debian version: ${VERSION_ID:-unknown}" ;; esac
}

validate_json() {
    local file=$1 mode=$2
    REFLECTOR_JSON="$file" REFLECTOR_MODE="$mode" python3 - <<'PY_JSON'
import json
import os
import sys

path = os.environ["REFLECTOR_JSON"]
mode = os.environ["REFLECTOR_MODE"]
known = {"P25": {10200, 10201}, "NXDN": {65000}}[mode]

try:
    with open(path, "r", encoding="utf-8-sig") as source:
        data = json.load(source)
    if not isinstance(data, dict):
        raise ValueError("top level is not an object")
    if not isinstance(data.get("_refcheck_metadata"), dict):
        raise ValueError("RefCheck metadata is missing")
    rows = data.get("reflectors")
    if not isinstance(rows, list) or len(rows) < 200:
        raise ValueError("reflectors array is missing or undersized")
    seen = set()
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("reflector record is not an object")
        designator = row.get("designator")
        if type(designator) is not int or not 1 <= designator <= 9999999:
            raise ValueError("invalid reflector designator")
        if designator in seen:
            raise ValueError("duplicate reflector designator")
        seen.add(designator)
        port = row.get("port")
        if type(port) is not int or not 1 <= port <= 65535:
            raise ValueError("invalid reflector port")
        for field in ("name", "sponsor"):
            if row.get(field) is not None and not isinstance(row[field], str):
                raise ValueError(f"invalid {field} value")
    missing = known - seen
    if missing:
        raise ValueError(f"known reflector is missing: {min(missing)}")
except Exception as exc:
    print(f"ERROR: {mode} JSON validation failed: {exc}", file=sys.stderr)
    sys.exit(1)

print(f"PASS: {mode} JSON validated ({len(rows)} reflectors)")
PY_JSON
}

patch_candidate() {
    local candidate=$1 current_hash
    current_hash=$(sha256sum "$TARGET" | awk '{print $1}')
    if ! grep -Fq "$MOD_MARKER" "$TARGET" && [[ "$current_hash" != "$STAGE2_HASH" ]]; then
        die "Unsupported dvswitch.sh. Expected the completed Stage 2 updater ($STAGE2_HASH), found $current_hash."
    fi

    DVSWITCH_CANDIDATE="$candidate" python3 - <<'PY_PATCH'
from pathlib import Path
import os

path = Path(os.environ["DVSWITCH_CANDIDATE"])
text = path.read_text(encoding="utf-8")
marker = "# DVSwitch-Mods: P25/NXDN JSON updater modification"
stage2 = "# DVSwitch-Mods: safe TXT database updater repair"

calls = '''        downloadAndValidateDatabase "NXDNHosts.txt" "https://hostfiles.refcheck.radio/NXDNHosts.txt" NXDN
        downloadAndValidateDatabase "P25Hosts.txt" "https://hostfiles.refcheck.radio/P25Hosts.txt" P25'''

modified_calls = '''        downloadAndValidateDatabase "NXDNHosts.txt" "https://hostfiles.refcheck.radio/NXDNHosts.txt" NXDN
        downloadAndValidateReflectorJSON NXDN
        downloadAndValidateDatabase "P25Hosts.txt" "https://hostfiles.refcheck.radio/P25Hosts.txt" P25
        downloadAndValidateReflectorJSON P25'''

function_anchor = '''#################################################################
# Compatibility wrapper for remaining stock Pi-Star TXT feeds.
#################################################################
function downloadAndValidate() {'''

json_function = r'''# DVSwitch-Mods: P25/NXDN JSON updater modification
#################################################################
# Download, validate, and atomically install dashboard JSON data.
#################################################################
function downloadAndValidateReflectorJSON() {
    declare _mode="$1" _name="${1}Hosts.json"
    declare _url="https://hostfiles.refcheck.radio/${_name}"
    declare _live="${MMDVM_DIR}/${_name}" _candidate _recordCount=0 _fileSize=0

    _candidate=$(mktemp "${MMDVM_DIR}/.${_name}.download.XXXXXX") || {
        echo "Error, unable to create temporary file for ${_name}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    }

    if ! ${DEBUG} curl --fail --location --silent --show-error \
        --user-agent "DVSwitch" --connect-timeout 10 --max-time 60 \
        --retry 3 --retry-delay 2 -o "${_candidate}" "${_url}"; then
        echo "Warning, ${_name} download failure; keeping existing ${_name}"
        rm -f -- "${_candidate}"
        _ERRORCODE=$ERROR_FILE_NOT_FOUND
        return
    fi

    if ! REFLECTOR_JSON="${_candidate}" REFLECTOR_MODE="${_mode}" python3 - <<'PY_REFLECTOR_JSON'
import json
import os
import sys

path = os.environ["REFLECTOR_JSON"]
mode = os.environ["REFLECTOR_MODE"]
known = {"P25": {10200, 10201}, "NXDN": {65000}}[mode]
try:
    with open(path, "r", encoding="utf-8-sig") as source:
        data = json.load(source)
    if not isinstance(data, dict) or not isinstance(data.get("_refcheck_metadata"), dict):
        raise ValueError("invalid RefCheck wrapper")
    rows = data.get("reflectors")
    if not isinstance(rows, list) or len(rows) < 200:
        raise ValueError("reflectors array is missing or undersized")
    seen = set()
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("record is not an object")
        designator, port = row.get("designator"), row.get("port")
        if type(designator) is not int or not 1 <= designator <= 9999999 or designator in seen:
            raise ValueError("invalid or duplicate designator")
        seen.add(designator)
        if type(port) is not int or not 1 <= port <= 65535:
            raise ValueError("invalid port")
        for field in ("name", "sponsor"):
            if row.get(field) is not None and not isinstance(row[field], str):
                raise ValueError("invalid " + field)
    if not known.issubset(seen):
        raise ValueError("known reflector is missing")
    print(len(rows))
except Exception as exc:
    print(f"{mode} JSON validation failed: {exc}", file=sys.stderr)
    sys.exit(1)
PY_REFLECTOR_JSON
    then
        echo "Error, downloaded ${_name} failed JSON validation; keeping existing file"
        rm -f -- "${_candidate}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    _recordCount=$(REFLECTOR_JSON="${_candidate}" python3 -c 'import json,os; print(len(json.load(open(os.environ["REFLECTOR_JSON"], encoding="utf-8-sig"))["reflectors"]))')
    _fileSize=$(wc -c < "${_candidate}")
    if ! installValidatedDatabase "${_candidate}" "${_live}"; then
        echo "Error, unable to install validated ${_name}"
        rm -f -- "${_candidate}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi
    echo "${_name} downloaded and validated successfully (${_recordCount} records, ${_fileSize} bytes)"
}

'''

if text.count(stage2) != 1:
    raise SystemExit("ERROR: completed Stage 2 marker is missing or ambiguous")

if text.count(marker) == 1:
    if text.count("function downloadAndValidateReflectorJSON()") != 1 or text.count(modified_calls) != 1:
        raise SystemExit("ERROR: incomplete or ambiguous JSON modification")
    if calls in text:
        raise SystemExit("ERROR: mixed unmodified and modified JSON call block")
elif text.count(marker) == 0:
    if text.count(function_anchor) != 1 or text.count(calls) != 1:
        raise SystemExit("ERROR: supported Stage 2 insertion anchors are missing or ambiguous")
    if "P25Hosts.json" in text or "NXDNHosts.json" in text:
        raise SystemExit("ERROR: unexpected existing JSON updater code")
    text = text.replace(function_anchor, json_function + function_anchor, 1)
    text = text.replace(calls, modified_calls, 1)
    path.write_text(text, encoding="utf-8")
else:
    raise SystemExit("ERROR: duplicate JSON modification markers")
PY_PATCH
}

prepare_candidate() {
    WORK_DIR=$(mktemp -d /tmp/dvswitch-json-mod.XXXXXX)
    cp -- "$TARGET" "$WORK_DIR/dvswitch.sh"
    patch_candidate "$WORK_DIR/dvswitch.sh"
    bash -n "$WORK_DIR/dvswitch.sh"
    local first_hash
    first_hash=$(sha256sum "$WORK_DIR/dvswitch.sh")
    patch_candidate "$WORK_DIR/dvswitch.sh"
    [[ "$first_hash" == "$(sha256sum "$WORK_DIR/dvswitch.sh")" ]] || die "Embedded patch is not idempotent."
}

download_candidate() {
    local mode=$1 output="$WORK_DIR/${1}Hosts.json"
    curl --fail --location --silent --show-error --user-agent "DVSwitch" \
        --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 2 \
        -o "$output" "https://hostfiles.refcheck.radio/${mode}Hosts.json"
    [[ -s "$output" ]] || die "$mode JSON download is empty."
    validate_json "$output" "$mode"
}

begin_backup() {
    local timestamp candidate counter=0
    install -d -o root -g root -m 0700 "$BACKUP_ROOT"
    timestamp=$(date +%Y%m%d-%H%M%S)
    candidate="$BACKUP_ROOT/install-$timestamp"
    while [[ -e "$candidate" ]]; do counter=$((counter + 1)); candidate="$BACKUP_ROOT/install-$timestamp-$counter"; done
    install -d -o root -g root -m 0700 "$candidate"
    cp -a -- "$TARGET" "$candidate/dvswitch.sh"
    for name in P25Hosts.json NXDNHosts.json; do
        if [[ -e "$DATA_DIR/$name" || -L "$DATA_DIR/$name" ]]; then
            require_regular_file "$DATA_DIR/$name"
            cp -a -- "$DATA_DIR/$name" "$candidate/$name"
        else
            : > "$candidate/$name.absent"
            chmod 0600 "$candidate/$name.absent"
        fi
    done
    ACTIVE_BACKUP="$candidate"
    printf 'Backup: %s\n' "$ACTIVE_BACKUP"
}

atomic_replace_script() {
    local temporary
    temporary=$(mktemp --tmpdir="$(dirname "$TARGET")" .dvswitch-json-mod.XXXXXX)
    cp -- "$WORK_DIR/dvswitch.sh" "$temporary"
    chown --reference="$TARGET" "$temporary"
    chmod --reference="$TARGET" "$temporary"
    mv -fT -- "$temporary" "$TARGET"
}

atomic_install_json() {
    local name=$1 target="$DATA_DIR/$1" temporary
    [[ ! -L "$target" ]] || die "Refusing symbolic-link target: $target"
    [[ ! -e "$target" || -f "$target" ]] || die "Refusing non-regular target: $target"
    temporary=$(mktemp --tmpdir="$DATA_DIR" ".${name}.install.XXXXXX")
    install -o root -g root -m 0644 "$WORK_DIR/$name" "$temporary"
    mv -fT -- "$temporary" "$target"
}

restore_backup_dir() {
    local directory=$1 name target temporary
    require_regular_file "$directory/dvswitch.sh"
    temporary=$(mktemp --tmpdir="$(dirname "$TARGET")" .dvswitch-json-restore.XXXXXX)
    cp -a -- "$directory/dvswitch.sh" "$temporary"
    mv -fT -- "$temporary" "$TARGET"
    for name in P25Hosts.json NXDNHosts.json; do
        target="$DATA_DIR/$name"
        if [[ -f "$directory/$name" && ! -L "$directory/$name" ]]; then
            temporary=$(mktemp --tmpdir="$DATA_DIR" ".${name}.restore.XXXXXX")
            cp -a -- "$directory/$name" "$temporary"
            mv -fT -- "$temporary" "$target"
        elif [[ -f "$directory/$name.absent" && ! -L "$directory/$name.absent" ]]; then
            rm -f -- "$target"
        else
            die "Backup state is missing for $name."
        fi
    done
    bash -n "$TARGET"
}

on_error() {
    local line=$1 status=$2
    trap - ERR
    set +e
    printf 'ERROR: failed near line %s (status %s).\n' "$line" "$status" >&2
    if [[ $INSTALL_ACTIVE -eq 1 && -n "$ACTIVE_BACKUP" ]]; then
        restore_backup_dir "$ACTIVE_BACKUP" && printf 'Automatic rollback completed.\n' >&2
    fi
    cleanup
    exit "$status"
}
trap 'on_error $LINENO $?' ERR
trap cleanup EXIT

preflight() {
    check_platform
    for command in awk bash chmod chown cmp cp curl date grep install mktemp mv python3 rm sha256sum stat; do require_command "$command"; done
    require_regular_file "$TARGET"
    [[ -d "$DATA_DIR" && ! -L "$DATA_DIR" ]] || die "Required data directory is unavailable: $DATA_DIR"
    bash -n "$TARGET"
}

verify_installed() {
    cmp -s "$WORK_DIR/dvswitch.sh" "$TARGET" || die "Installed dvswitch.sh does not match the validated candidate."
    bash -n "$TARGET"
    [[ $(grep -Fc "$MOD_MARKER" "$TARGET") -eq 1 ]] || die "Installed modification marker is missing or duplicated."
    for mode in P25 NXDN; do
        require_regular_file "$DATA_DIR/${mode}Hosts.json"
        [[ $(stat -c '%U:%G:%a' "$DATA_DIR/${mode}Hosts.json") == root:root:644 ]] || die "Incorrect metadata on ${mode}Hosts.json."
        validate_json "$DATA_DIR/${mode}Hosts.json" "$mode"
    done
}

run_check() {
    preflight
    prepare_candidate
    if cmp -s "$TARGET" "$WORK_DIR/dvswitch.sh"; then
        printf 'ALREADY MODIFIED: %s\n' "$TARGET"
    else
        printf 'MODIFICATION READY: %s\nBefore: ' "$TARGET"
        sha256sum "$TARGET"
        printf 'After:  '
        sha256sum "$WORK_DIR/dvswitch.sh"
    fi
    printf 'PASS: supported completed Stage 2 updater. No files changed.\n'
}

run_install() {
    preflight
    prepare_candidate
    if cmp -s "$TARGET" "$WORK_DIR/dvswitch.sh" && \
       [[ -f "$DATA_DIR/P25Hosts.json" && ! -L "$DATA_DIR/P25Hosts.json" ]] && \
       [[ -f "$DATA_DIR/NXDNHosts.json" && ! -L "$DATA_DIR/NXDNHosts.json" ]] && \
       validate_json "$DATA_DIR/P25Hosts.json" P25 >/dev/null && \
       validate_json "$DATA_DIR/NXDNHosts.json" NXDN >/dev/null; then
        printf 'ALREADY MODIFIED: P25/NXDN JSON updater and validated databases are installed.\n'
        return
    fi

    download_candidate P25
    download_candidate NXDN
    begin_backup
    INSTALL_ACTIVE=1
    atomic_replace_script
    atomic_install_json P25Hosts.json
    atomic_install_json NXDNHosts.json
    verify_installed
    INSTALL_ACTIVE=0
    printf 'PASS: P25/NXDN JSON updater modification installed and verified.\nBackup: %s\n' "$ACTIVE_BACKUP"
}

run_restore() {
    local name=$1 directory
    preflight
    [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $name"
    directory="$BACKUP_ROOT/$name"
    [[ -d "$directory" && ! -L "$directory" ]] || die "Backup not found: $name"
    restore_backup_dir "$directory"
    printf 'PASS: dvswitch.sh and P25/NXDN JSON state restored from %s.\n' "$name"
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
