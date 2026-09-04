#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI
# Clean the DVSwitch Gateway and Local Activity Target columns.

set -euo pipefail

readonly SCRIPT_VERSION="1.1.3"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly LH_TARGET="/usr/share/dvswitch/include/lh.php"
readonly LOCALTX_TARGET="/usr/share/dvswitch/include/localtx.php"
readonly HELPER_TARGET="/usr/share/dvswitch/include/dvswitch_mods_target_display.php"
readonly HELPER_SOURCE="$SCRIPT_DIR/lib/dvswitch_mods_target_display.php"
readonly PATCHER="$SCRIPT_DIR/lib/patch_dashboard_targets.py"
readonly TRANSACTION_LIBRARY="$SCRIPT_DIR/lib/transaction.sh"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-targets"
WORK_DIR=""
INSTALL_ACTIVE=0

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
rollback() { local status=$?; if (( INSTALL_ACTIVE )); then dvsm_transaction_rollback || true; fi; cleanup; exit "$status"; }
trap rollback EXIT INT TERM HUP

usage() {
    printf 'DVSwitch activity Target display modification %s\nUsage: sudo %s {--check|--install|--restore BACKUP-NAME}\n' "$SCRIPT_VERSION" "$(basename "$0")"
}

require_regular_file() { [[ -f "$1" && ! -L "$1" ]] || die "Required regular file not found: $1"; }
file_hash() { sha256sum "$1" | awk '{print $1}'; }

preflight() {
    [[ $EUID -eq 0 ]] || die "Run this command with sudo."
    command -v python3 >/dev/null || die "python3 is required."
    command -v php >/dev/null || die "php is required."
    for path in "$LH_TARGET" "$LOCALTX_TARGET" "$HELPER_SOURCE" "$PATCHER" "$TRANSACTION_LIBRARY"; do require_regular_file "$path"; done
}

prepare_candidates() {
    WORK_DIR=$(mktemp -d /tmp/dvswitch-targets.XXXXXX)
    cp -- "$LH_TARGET" "$WORK_DIR/lh.php"
    cp -- "$LOCALTX_TARGET" "$WORK_DIR/localtx.php"
    python3 "$PATCHER" --lh "$WORK_DIR/lh.php" --localtx "$WORK_DIR/localtx.php"
    php -l "$WORK_DIR/lh.php" >/dev/null
    php -l "$WORK_DIR/localtx.php" >/dev/null
    php -l "$HELPER_SOURCE" >/dev/null
    local lh_hash localtx_hash
    lh_hash=$(file_hash "$WORK_DIR/lh.php")
    localtx_hash=$(file_hash "$WORK_DIR/localtx.php")
    python3 "$PATCHER" --lh "$WORK_DIR/lh.php" --localtx "$WORK_DIR/localtx.php"
    [[ "$lh_hash" == "$(file_hash "$WORK_DIR/lh.php")" && "$localtx_hash" == "$(file_hash "$WORK_DIR/localtx.php")" ]] || die "Dashboard patch is not idempotent."
}

show_result() {
    local helper_same=0
    [[ -f "$HELPER_TARGET" && ! -L "$HELPER_TARGET" ]] && cmp -s "$HELPER_SOURCE" "$HELPER_TARGET" && helper_same=1
    if cmp -s "$LH_TARGET" "$WORK_DIR/lh.php" && cmp -s "$LOCALTX_TARGET" "$WORK_DIR/localtx.php" && (( helper_same )); then
        printf 'ALREADY MODIFIED: cleaned Gateway and Local Activity Target display is installed.\n'
    else
        printf 'MODIFICATION READY:\nBefore lh.php:      %s\nAfter lh.php:       %s\nBefore localtx.php: %s\nAfter localtx.php:  %s\n' \
            "$(file_hash "$LH_TARGET")" "$(file_hash "$WORK_DIR/lh.php")" "$(file_hash "$LOCALTX_TARGET")" "$(file_hash "$WORK_DIR/localtx.php")"
    fi
}

check_health() {
    php -l "$LH_TARGET" >/dev/null
    php -l "$LOCALTX_TARGET" >/dev/null
    [[ ! -f "$HELPER_TARGET" ]] || php -l "$HELPER_TARGET" >/dev/null
    systemctl is-active --quiet apache2 || die "apache2 is not active."
}

run_check() {
    preflight
    prepare_candidates
    show_result
    printf 'PASS: supported activity Target display structure. No files changed.\n'
}

run_install() {
    preflight
    prepare_candidates
    show_result
    if cmp -s "$LH_TARGET" "$WORK_DIR/lh.php" && cmp -s "$LOCALTX_TARGET" "$WORK_DIR/localtx.php" && [[ -f "$HELPER_TARGET" && ! -L "$HELPER_TARGET" ]] && cmp -s "$HELPER_SOURCE" "$HELPER_TARGET"; then
        check_health
        printf 'PASS: activity Target display modification is already installed. No files changed.\n'
        return
    fi
    if [[ -e "$HELPER_TARGET" || -L "$HELPER_TARGET" ]]; then
        [[ -f "$HELPER_TARGET" && ! -L "$HELPER_TARGET" ]] || die "Refusing unsupported helper target state: $HELPER_TARGET"
    fi
    . "$TRANSACTION_LIBRARY"
    dvsm_transaction_begin "$BACKUP_ROOT"
    INSTALL_ACTIVE=1
    if ! cmp -s "$WORK_DIR/lh.php" "$LH_TARGET"; then
        dvsm_backup_file "$LH_TARGET"
        dvsm_install_candidate "$WORK_DIR/lh.php" "$LH_TARGET"
    fi
    if ! cmp -s "$WORK_DIR/localtx.php" "$LOCALTX_TARGET"; then
        dvsm_backup_file "$LOCALTX_TARGET"
        dvsm_install_candidate "$WORK_DIR/localtx.php" "$LOCALTX_TARGET"
    fi
    if [[ ! -f "$HELPER_TARGET" ]]; then
        dvsm_record_absent_file "$HELPER_TARGET"
        dvsm_install_new_candidate "$HELPER_SOURCE" "$HELPER_TARGET" root root 0644
    elif ! cmp -s "$HELPER_SOURCE" "$HELPER_TARGET"; then
        dvsm_backup_file "$HELPER_TARGET"
        dvsm_install_candidate "$HELPER_SOURCE" "$HELPER_TARGET"
    fi
    cmp -s "$WORK_DIR/lh.php" "$LH_TARGET"
    cmp -s "$WORK_DIR/localtx.php" "$LOCALTX_TARGET"
    cmp -s "$HELPER_SOURCE" "$HELPER_TARGET"
    python3 "$PATCHER" --lh "$LH_TARGET" --localtx "$LOCALTX_TARGET"
    check_health
    INSTALL_ACTIVE=0
    printf 'PASS: activity Target display modification installed atomically.\nBackup: %s\n' "$DVSM_TRANSACTION_DIR"
}

run_restore() {
    local name=$1
    preflight
    [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $name"
    local directory="$BACKUP_ROOT/$name"
    require_regular_file "$directory/MANIFEST"
    awk -F '\t' -v lh="$LH_TARGET" -v localtx="$LOCALTX_TARGET" -v helper="$HELPER_TARGET" '
        NF != 3 || ($1 != "0" && $1 != "1") || ($2 != lh && $2 != localtx && $2 != helper) { bad=1 }
        { seen[$2]++ }
        END {
            if (NR < 1 || NR > 3) bad=1
            for (target in seen) if (seen[target] != 1) bad=1
            exit bad
        }
    ' "$directory/MANIFEST" || die "Backup manifest is not a supported Target-modification backup."
    . "$TRANSACTION_LIBRARY"
    dvsm_restore_backup_set "$directory"
    php -l "$LH_TARGET" >/dev/null
    php -l "$LOCALTX_TARGET" >/dev/null
    [[ ! -f "$HELPER_TARGET" ]] || php -l "$HELPER_TARGET" >/dev/null
    check_health
    printf 'PASS: activity Target display restored from %s.\n' "$name"
}

case ${1:-} in
    --check) [[ $# -eq 1 ]] || { usage >&2; exit 2; }; run_check ;;
    --install) [[ $# -eq 1 ]] || { usage >&2; exit 2; }; run_install ;;
    --restore) [[ $# -eq 2 ]] || { usage >&2; exit 2; }; run_restore "$2" ;;
    *) usage >&2; exit 2 ;;
esac

cleanup
trap - EXIT INT TERM HUP
