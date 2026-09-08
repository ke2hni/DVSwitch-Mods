#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Show the selected DMR network and talkgroup name in the DVSwitch Dashboard
# DMR Master card. BrandMeister data is also used for STFU. This is display-only.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="1.5.0"
readonly TARGET="/usr/share/dvswitch/include/status.php"
readonly BM_LIST="/var/lib/mmdvm/TGList_BM.txt"
readonly TGIF_LIST="/var/lib/mmdvm/TGList_TGIF.txt"
readonly STATE_FILE="/var/lib/mmdvm/dvswitch-mods-dmr-state.json"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/dmr-friendly-names"
readonly MOD_MARKER="// DVSwitch-Mods: DMR Master friendly-name display v7"

WORK_DIR=""
ACTIVE_BACKUP=""
INSTALL_ACTIVE=0

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
usage() { printf 'DMR Master friendly-name modification %s\nUsage: sudo %s {--check|--install|--restore BACKUP-NAME}\n' "$SCRIPT_VERSION" "$(basename "$0")"; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
require_regular_file() { [[ -f "$1" && ! -L "$1" ]] || die "Required regular non-symlink file not found: $1"; }
file_hash() { sha256sum "$1" | awk '{print $1}'; }

check_platform() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this modification with sudo."
    [[ -r /etc/os-release ]] || die "/etc/os-release is unavailable."
    . /etc/os-release
    [[ ${ID:-} == debian ]] || die "Unsupported OS: ${ID:-unknown}"
    case "${VERSION_ID:-}" in 12|13) ;; *) die "Unsupported Debian version: ${VERSION_ID:-unknown}" ;; esac
}

validate_tg_list() {
    local file=$1 network=$2 minimum=$3 sentinel=$4
    TG_FILE="$file" TG_NETWORK="$network" TG_MINIMUM="$minimum" TG_SENTINEL="$sentinel" python3 - <<'PY_LIST'
import os
import sys

path = os.environ["TG_FILE"]
network = os.environ["TG_NETWORK"]
minimum = int(os.environ["TG_MINIMUM"])
sentinel = os.environ["TG_SENTINEL"]
seen = set()
try:
    with open(path, "r", encoding="utf-8-sig") as source:
        for raw in source:
            line = raw.rstrip("\r\n")
            if not line or line.startswith("#"):
                continue
            fields = line.split(";", 3)
            if len(fields) != 4 or not fields[0].isdigit() or fields[1] not in ("0", "1"):
                raise ValueError("invalid talkgroup record")
            number = int(fields[0])
            if not 1 <= number <= 9999999 or number in seen:
                raise ValueError("invalid or duplicate talkgroup number")
            if fields[1] == "0" and fields[3] != "TG" + fields[0]:
                raise ValueError("invalid description field")
            if fields[1] == "1" and fields[3] != "REF" + fields[0]:
                raise ValueError("invalid reflector description field")
            seen.add(number)
    if len(seen) < minimum or int(sentinel) not in seen:
        raise ValueError("talkgroup list failed sanity checks")
except Exception as exc:
    print(f"ERROR: {network} talkgroup list validation failed: {exc}", file=sys.stderr)
    sys.exit(1)
PY_LIST
}

validate_state_file() {
    [[ ! -e "$STATE_FILE" ]] && return 0
    require_regular_file "$STATE_FILE"
    DMR_STATE="$STATE_FILE" python3 - <<'PY_STATE'
import json
import os
import sys

try:
    with open(os.environ["DMR_STATE"], "r", encoding="utf-8") as source:
        state = json.load(source)
    if not isinstance(state, dict):
        raise ValueError("top level is not an object")
    for key, value in state.items():
        if key == "current_network":
            if value not in ("BM", "TGIF"):
                raise ValueError("invalid current network")
            continue
        if key == "observed_mode":
            if value not in ("DMR", "STFU", "YSF", "YSFN", "YSFW", "P25", "NXDN", "DSTAR", "ASL"):
                raise ValueError("invalid observed mode")
            continue
        if key == "observed_network":
            if value not in ("BM", "TGIF"):
                raise ValueError("invalid observed network")
            continue
        if key in ("observed_tg", "blocked_tg"):
            if not isinstance(value, str) or not value.isdigit() or value == "0":
                raise ValueError("invalid transition talkgroup")
            continue
        if key not in ("BM", "TGIF") or not isinstance(value, dict):
            raise ValueError("invalid network state")
        tg = str(value.get("tg", ""))
        if not tg.isdigit() or tg == "0":
            raise ValueError("invalid saved talkgroup")
except Exception as exc:
    print(f"ERROR: DMR state validation failed: {exc}", file=sys.stderr)
    sys.exit(1)
PY_STATE
}

patch_candidate() {
    STATUS_CANDIDATE="$WORK_DIR/status.php" \
        DVS_MOD_MARKER="$MOD_MARKER" \
        python3 "$SCRIPT_DIR/lib/patch_dashboard_dmr.py"
}

prepare_candidate() {
    WORK_DIR=$(mktemp -d /tmp/dvswitch-dmr-friendly.XXXXXX)
    cp -- "$TARGET" "$WORK_DIR/status.php"
    patch_candidate
    php -l "$WORK_DIR/status.php" >/dev/null
    local first_hash
    first_hash=$(file_hash "$WORK_DIR/status.php")
    patch_candidate
    [[ "$first_hash" == "$(file_hash "$WORK_DIR/status.php")" ]] || die "Embedded patch is not idempotent."
}

begin_backup() {
    local timestamp candidate counter=0
    install -d -o root -g root -m 0700 "$BACKUP_ROOT"
    timestamp=$(date +%Y%m%d-%H%M%S)
    candidate="$BACKUP_ROOT/install-$timestamp"
    while [[ -e "$candidate" ]]; do counter=$((counter + 1)); candidate="$BACKUP_ROOT/install-$timestamp-$counter"; done
    install -d -o root -g root -m 0700 "$candidate"
    cp -a -- "$TARGET" "$candidate/status.php"
    if [[ -e "$STATE_FILE" ]]; then
        require_regular_file "$STATE_FILE"
        cp -a -- "$STATE_FILE" "$candidate/dmr-state.json"
    else
        : > "$candidate/state-was-absent"
    fi
    ACTIVE_BACKUP="$candidate"
}

prepare_state() {
    if [[ -e "$STATE_FILE" ]]; then
        require_regular_file "$STATE_FILE"
        validate_state_file
        chown root:www-data "$STATE_FILE"
        chmod 0664 "$STATE_FILE"
    else
        printf '{}\n' > "$STATE_FILE"
        chown root:www-data "$STATE_FILE"
        chmod 0664 "$STATE_FILE"
    fi
}

atomic_replace() {
    local temporary
    temporary=$(mktemp --tmpdir="$(dirname "$TARGET")" .dvswitch-dmr-friendly.XXXXXX)
    cp -- "$WORK_DIR/status.php" "$temporary"
    chown --reference="$TARGET" "$temporary"
    chmod --reference="$TARGET" "$temporary"
    mv -fT -- "$temporary" "$TARGET"
}

restore_backup_dir() {
    local directory=$1 temporary state_temporary
    require_regular_file "$directory/status.php"
    temporary=$(mktemp --tmpdir="$(dirname "$TARGET")" .dvswitch-dmr-friendly-restore.XXXXXX)
    cp -a -- "$directory/status.php" "$temporary"
    mv -fT -- "$temporary" "$TARGET"
    if [[ -f "$directory/dmr-state.json" && ! -L "$directory/dmr-state.json" ]]; then
        state_temporary=$(mktemp --tmpdir="$(dirname "$STATE_FILE")" .dvswitch-dmr-state-restore.XXXXXX)
        cp -a -- "$directory/dmr-state.json" "$state_temporary"
        mv -fT -- "$state_temporary" "$STATE_FILE"
    elif [[ -f "$directory/state-was-absent" && ! -L "$directory/state-was-absent" ]]; then
        rm -f -- "$STATE_FILE"
    else
        return 1
    fi
    php -l "$TARGET" >/dev/null
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

preflight_common() {
    check_platform
    for command in awk bash chmod chown cmp cp date getent grep install mktemp mv php python3 rm sha256sum; do require_command "$command"; done
    require_regular_file "$TARGET"
    getent group www-data >/dev/null || die "Required group not found: www-data"
    php -l "$TARGET" >/dev/null
}

preflight_install() {
    preflight_common
    require_regular_file "$BM_LIST"
    require_regular_file "$TGIF_LIST"
    validate_tg_list "$BM_LIST" BrandMeister 1000 3100
    validate_tg_list "$TGIF_LIST" TGIF 100 31665
    validate_state_file
}

verify_installed() {
    if ! cmp -s "$WORK_DIR/status.php" "$TARGET"; then printf 'ERROR: installed status.php does not match the validated candidate.\n' >&2; return 1; fi
    if ! php -l "$TARGET" >/dev/null; then printf 'ERROR: installed status.php failed PHP syntax validation.\n' >&2; return 1; fi
    if [[ $(grep -Fc "$MOD_MARKER" "$TARGET") -ne 1 ]]; then printf 'ERROR: installed modification marker is missing or duplicated.\n' >&2; return 1; fi
    if [[ $(grep -Fc 'dvsModsDmrMasterDisplay($dmrMasterHost, $abinfo)' "$TARGET") -ne 1 ]]; then printf 'ERROR: DMR Master display wrapper is missing or duplicated.\n' >&2; return 1; fi
    if [[ $(grep -Fc 'dvsModsDmrMasterHeading($dmrMasterHost, $abinfo)' "$TARGET") -ne 1 ]]; then printf 'ERROR: DMR Master network heading wrapper is missing or duplicated.\n' >&2; return 1; fi
    if [[ $(grep -Fc 'white-space:normal;word-break:normal;overflow-wrap:anywhere;text-align:center;' "$TARGET") -ne 1 ]]; then printf 'ERROR: DMR Master wrapping style is missing or duplicated.\n' >&2; return 1; fi
    if [[ $(grep -Fc "\$dmrstat === '' && file_exists(\"/var/log/mmdvm/MMDVM_Bridge-\".gmdate(\"Y-m-d\", time() - 86340).\".log\")" "$TARGET") -ne 1 ]]; then printf 'ERROR: DMR previous-log fallback is missing or duplicated.\n' >&2; return 1; fi
    if grep -Fq 'strpos($dmrstatus,' "$TARGET"; then printf 'ERROR: obsolete DMR status variable remains installed.\n' >&2; return 1; fi
    if [[ $(grep -Fc '>Tx TG/Ref</th>' "$TARGET") -ne 2 ]]; then printf 'ERROR: D-Star Tx TG/Ref labels were not preserved.\n' >&2; return 1; fi
    if [[ $(grep -Fc 'formatReflectorLink(' "$TARGET") -ne 2 ]]; then printf 'ERROR: P25/NXDN friendly-name wrappers were not preserved.\n' >&2; return 1; fi
    if [[ ! -f "$STATE_FILE" || -L "$STATE_FILE" ]]; then printf 'ERROR: DMR state file is missing or unsafe.\n' >&2; return 1; fi
    [[ $(stat -c '%U:%G:%a' "$STATE_FILE") == root:www-data:664 ]] || { printf 'ERROR: DMR state file metadata is incorrect.\n' >&2; return 1; }
    if ! validate_state_file; then printf 'ERROR: DMR state file validation failed.\n' >&2; return 1; fi
}

run_check() {
    preflight_install
    prepare_candidate
    if cmp -s "$TARGET" "$WORK_DIR/status.php"; then
        printf 'ALREADY MODIFIED: DMR Master friendly-name display is installed.\n'
    else
        printf 'MODIFICATION READY:\nBefore status.php: %s\nAfter status.php:  %s\n' "$(file_hash "$TARGET")" "$(file_hash "$WORK_DIR/status.php")"
    fi
    printf 'PASS: supported dashboard and DMR talkgroup-list structure. No files changed.\n'
}

run_install() {
    preflight_install
    prepare_candidate
    if cmp -s "$TARGET" "$WORK_DIR/status.php"; then
        verify_installed
        printf 'PASS: DMR Master friendly-name modification is already installed.\n'
        return
    fi
    begin_backup
    INSTALL_ACTIVE=1
    prepare_state
    atomic_replace
    if ! verify_installed; then
        if restore_backup_dir "$ACTIVE_BACKUP"; then
            INSTALL_ACTIVE=0
            die "Installation validation failed; automatic rollback completed."
        fi
        die "Installation validation failed and automatic rollback failed; use the protected backup."
    fi
    INSTALL_ACTIVE=0
    printf 'PASS: DMR Master friendly-name modification installed atomically.\nBackup: %s\n' "$ACTIVE_BACKUP"
}

run_restore() {
    local name=$1 directory
    preflight_common
    [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $name"
    directory="$BACKUP_ROOT/$name"
    [[ -d "$directory" && ! -L "$directory" ]] || die "Protected backup not found: $name"
    restore_backup_dir "$directory" || die "Protected backup is incomplete or restoration failed."
    printf 'PASS: DMR dashboard files restored from %s.\n' "$name"
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
