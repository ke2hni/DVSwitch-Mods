#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Add STFU's independent ODMR log to Gateway Activity, Local Activity, and TRX Info.
set -Eeuo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly FUNCTIONS="/usr/share/dvswitch/include/functions.php"
readonly LH="/usr/share/dvswitch/include/lh.php"
readonly LOCALTX="/usr/share/dvswitch/include/localtx.php"
readonly STATUS="/usr/share/dvswitch/include/status.php"
readonly HELPER="/usr/share/dvswitch/include/dvswitch_mods_stfu_activity.php"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-stfu-activity"
readonly PATCHER="$SCRIPT_DIR/lib/patch_dashboard_stfu_activity.py"
readonly HELPER_SOURCE="$SCRIPT_DIR/lib/dvswitch_mods_stfu_activity.php"
readonly TRANSACTION_LIBRARY="$SCRIPT_DIR/lib/transaction.sh"

WORK_DIR=""
INSTALL_ACTIVE=0
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
require_regular() { [[ -f "$1" && ! -L "$1" ]] || die "Required regular file not found: $1"; }

rollback() {
    local status=$?
    if (( INSTALL_ACTIVE )); then dvsm_transaction_rollback || true; fi
    cleanup
    exit "$status"
}
trap rollback EXIT INT TERM HUP

preflight() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die 'Run this command with sudo.'
    command -v python3 >/dev/null || die 'python3 is required.'
    command -v php >/dev/null || die 'php is required.'
    for path in "$FUNCTIONS" "$LH" "$LOCALTX" "$STATUS" "$PATCHER" "$HELPER_SOURCE" "$TRANSACTION_LIBRARY"; do require_regular "$path"; done
    for path in "$HELPER"; do [[ ! -e "$path" || -f "$path" && ! -L "$path" ]] || die "Refusing unsupported target: $path"; done
    if [[ -e "$HELPER" ]] && ! grep -Eq 'DVSwitch-Mods: STFU activity feed v[12]$' "$HELPER"; then
        die "Refusing to replace an unrecognized helper: $HELPER"
    fi
}

prepare() {
    WORK_DIR=$(mktemp -d /tmp/dvswitch-stfu-activity.XXXXXX)
    cp -- "$FUNCTIONS" "$WORK_DIR/functions.php"
    cp -- "$LH" "$WORK_DIR/lh.php"
    cp -- "$LOCALTX" "$WORK_DIR/localtx.php"
    cp -- "$STATUS" "$WORK_DIR/status.php"
    python3 "$PATCHER" --functions "$WORK_DIR/functions.php" --lh "$WORK_DIR/lh.php" \
        --localtx "$WORK_DIR/localtx.php" --status "$WORK_DIR/status.php"
    cp -- "$HELPER_SOURCE" "$WORK_DIR/dvswitch_mods_stfu_activity.php"
    for file in "$WORK_DIR/functions.php" "$WORK_DIR/lh.php" "$WORK_DIR/localtx.php" "$WORK_DIR/status.php" "$WORK_DIR/dvswitch_mods_stfu_activity.php"; do
        php -l "$file" >/dev/null || die "PHP syntax validation failed: $file"
    done
    local first second
    for file in functions.php lh.php localtx.php status.php; do
        cp -- "$WORK_DIR/$file" "$WORK_DIR/first-$file"
    done
    python3 "$PATCHER" --functions "$WORK_DIR/functions.php" --lh "$WORK_DIR/lh.php" \
        --localtx "$WORK_DIR/localtx.php" --status "$WORK_DIR/status.php"
    for file in functions.php lh.php localtx.php status.php; do
        cmp -s "$WORK_DIR/first-$file" "$WORK_DIR/$file" || die "STFU dashboard patch is not idempotent: $file"
    done
}

is_installed() {
    cmp -s "$WORK_DIR/functions.php" "$FUNCTIONS" &&
    cmp -s "$WORK_DIR/lh.php" "$LH" &&
    cmp -s "$WORK_DIR/localtx.php" "$LOCALTX" &&
    cmp -s "$WORK_DIR/status.php" "$STATUS" &&
    cmp -s "$WORK_DIR/dvswitch_mods_stfu_activity.php" "$HELPER"
}

run_check() {
    preflight
    prepare
    if is_installed; then
        printf 'ALREADY MODIFIED: STFU Gateway, Local, and TRX activity integration is installed.\n'
    else
        printf 'MODIFICATION READY: STFU.log events can be added to Gateway Activity, Local Activity, and TRX Info.\n'
    fi
    printf 'PASS: STFU helper and dashboard structure are supported. No files changed.\n'
}

run_install() {
    local file target
    preflight
    prepare
    if is_installed; then
        printf 'PASS: STFU activity integration is already installed; no backup created.\n'
        return
    fi
    . "$TRANSACTION_LIBRARY"
    dvsm_transaction_begin "$BACKUP_ROOT"
    INSTALL_ACTIVE=1
    for file in functions.php lh.php localtx.php status.php; do
        case "$file" in
            functions.php) target=$FUNCTIONS ;;
            lh.php) target=$LH ;;
            localtx.php) target=$LOCALTX ;;
            status.php) target=$STATUS ;;
        esac
        dvsm_backup_file "$target"
        dvsm_install_candidate "$WORK_DIR/$file" "$target"
    done
    if [[ -e "$HELPER" ]]; then
        dvsm_backup_file "$HELPER"
        dvsm_install_candidate "$WORK_DIR/dvswitch_mods_stfu_activity.php" "$HELPER"
    else
        dvsm_record_absent_file "$HELPER"
        dvsm_install_new_candidate "$WORK_DIR/dvswitch_mods_stfu_activity.php" "$HELPER" root root 0644
    fi
    for target in "$FUNCTIONS" "$LH" "$LOCALTX" "$STATUS" "$HELPER"; do php -l "$target" >/dev/null || die "Installed PHP syntax validation failed: $target"; done
    INSTALL_ACTIVE=0
    printf 'PASS: STFU activity integration installed atomically.\nBackup: %s\n' "$DVSM_TRANSACTION_DIR"
}

run_uninstall() {
    local backup_name=${1:?backup name required} backup_dir
    [[ $EUID -eq 0 ]] || die 'Run this command with sudo.'
    [[ "$backup_name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $backup_name"
    backup_dir="$BACKUP_ROOT/$backup_name"
    [[ -d "$backup_dir" && ! -L "$backup_dir" ]] || die "Protected backup not found: $backup_name"
    . "$TRANSACTION_LIBRARY"
    dvsm_restore_backup_set "$backup_dir"
}

case "${1:-}" in
    --check) [[ $# -eq 1 ]] || die '--check takes no extra arguments.'; run_check ;;
    --install) [[ $# -eq 1 ]] || die '--install takes no extra arguments.'; run_install ;;
    --uninstall|--restore) [[ $# -eq 2 ]] || die '--uninstall requires one backup name.'; run_uninstall "$2" ;;
    --help|-h) printf 'STFU activity integration\nUsage: sudo %s {--check|--install|--uninstall BACKUP-NAME}\n' "$(basename "$0")" ;;
    *) die "Usage: sudo $(basename "$0") {--check|--install|--uninstall BACKUP-NAME}" ;;
esac
