#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Label each DMR activity row with the network active at its event timestamp.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="1.1.1"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly LH_TARGET="/usr/share/dvswitch/include/lh.php"
readonly LOCALTX_TARGET="/usr/share/dvswitch/include/localtx.php"
readonly HELPER_TARGET="/usr/share/dvswitch/include/dvswitch_mods_activity_mode.php"
readonly HELPER_SOURCE="$SCRIPT_DIR/lib/dvswitch_mods_activity_mode.php"
readonly HISTORY_CAPTURE_TARGET="/usr/local/sbin/dvswitch-mods-activity-mode-history"
readonly HISTORY_CAPTURE_SOURCE="$SCRIPT_DIR/lib/dvswitch_mods_activity_mode_history.py"
readonly HISTORY_SERVICE_TARGET="/etc/systemd/system/dvswitch-mods-activity-mode-history.service"
readonly HISTORY_SERVICE_SOURCE="$SCRIPT_DIR/systemd/dvswitch-mods-activity-mode-history.service"
readonly HISTORY_PATH_TARGET="/etc/systemd/system/dvswitch-mods-activity-mode-history.path"
readonly HISTORY_PATH_SOURCE="$SCRIPT_DIR/systemd/dvswitch-mods-activity-mode-history.path"
readonly PATCHER="$SCRIPT_DIR/lib/patch_dashboard_activity_modes.py"
readonly TRANSACTION_LIBRARY="$SCRIPT_DIR/lib/transaction.sh"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-activity-modes"

WORK_DIR=""
INSTALL_ACTIVE=0
TRACKER_WAS_ENABLED=0

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
rollback() {
    local status=$?
    if (( INSTALL_ACTIVE )); then
        systemctl disable --now dvswitch-mods-activity-mode-history.path >/dev/null 2>&1 || true
        systemctl stop dvswitch-mods-activity-mode-history.service >/dev/null 2>&1 || true
        systemctl daemon-reload >/dev/null 2>&1 || true
        dvsm_transaction_rollback || true
        systemctl daemon-reload >/dev/null 2>&1 || true
        if (( TRACKER_WAS_ENABLED )); then systemctl enable --now dvswitch-mods-activity-mode-history.path >/dev/null 2>&1 || true; fi
    fi
    cleanup
    exit "$status"
}
usage() { printf 'Dashboard activity mode labels %s\nUsage: sudo %s {--check|--install|--restore BACKUP-NAME}\n' "$SCRIPT_VERSION" "$(basename "$0")"; }
require_regular() { [[ -f "$1" && ! -L "$1" ]] || die "Required regular file not found: $1"; }
file_hash() { sha256sum "$1" | awk '{print $1}'; }

trap rollback EXIT INT TERM HUP

preflight() {
    [[ $EUID -eq 0 ]] || die 'Run this command with sudo.'
    command -v python3 >/dev/null || die 'python3 is required.'
    command -v php >/dev/null || die 'php is required.'
    command -v systemctl >/dev/null || die 'systemd is required for per-event mode history.'
    for path in "$LH_TARGET" "$LOCALTX_TARGET" "$HELPER_SOURCE" "$HISTORY_CAPTURE_SOURCE" "$HISTORY_SERVICE_SOURCE" "$HISTORY_PATH_SOURCE" "$PATCHER" "$TRANSACTION_LIBRARY"; do require_regular "$path"; done
    [[ ! -e "$HELPER_TARGET" || -f "$HELPER_TARGET" && ! -L "$HELPER_TARGET" ]] || die "Refusing unsupported helper target: $HELPER_TARGET"
    [[ ! -e "$HISTORY_CAPTURE_TARGET" || -f "$HISTORY_CAPTURE_TARGET" && ! -L "$HISTORY_CAPTURE_TARGET" ]] || die "Refusing unsupported history capture target: $HISTORY_CAPTURE_TARGET"
    [[ ! -e "$HISTORY_SERVICE_TARGET" || -f "$HISTORY_SERVICE_TARGET" && ! -L "$HISTORY_SERVICE_TARGET" ]] || die "Refusing unsupported systemd service target: $HISTORY_SERVICE_TARGET"
    [[ ! -e "$HISTORY_PATH_TARGET" || -f "$HISTORY_PATH_TARGET" && ! -L "$HISTORY_PATH_TARGET" ]] || die "Refusing unsupported systemd path target: $HISTORY_PATH_TARGET"
}

prepare_candidates() {
    WORK_DIR=$(mktemp -d /tmp/dvswitch-activity-modes.XXXXXX)
    cp -- "$LH_TARGET" "$WORK_DIR/lh.php"
    cp -- "$LOCALTX_TARGET" "$WORK_DIR/localtx.php"
    python3 "$PATCHER" --lh "$WORK_DIR/lh.php" --localtx "$WORK_DIR/localtx.php"
    php -l "$WORK_DIR/lh.php" >/dev/null || die 'Gateway Activity PHP syntax validation failed.'
    php -l "$WORK_DIR/localtx.php" >/dev/null || die 'Local Activity PHP syntax validation failed.'
    php -l "$HELPER_SOURCE" >/dev/null || die 'Activity mode helper PHP syntax validation failed.'
    python3 -c 'from pathlib import Path; compile(Path(__import__("sys").argv[1]).read_text(), __import__("sys").argv[1], "exec")' "$HISTORY_CAPTURE_SOURCE" || die 'Activity mode history recorder Python syntax validation failed.'
    local lh_hash localtx_hash
    lh_hash=$(file_hash "$WORK_DIR/lh.php")
    localtx_hash=$(file_hash "$WORK_DIR/localtx.php")
    python3 "$PATCHER" --lh "$WORK_DIR/lh.php" --localtx "$WORK_DIR/localtx.php"
    [[ "$lh_hash" == "$(file_hash "$WORK_DIR/lh.php")" && "$localtx_hash" == "$(file_hash "$WORK_DIR/localtx.php")" ]] || die 'Dashboard patch is not idempotent.'
}

show_result() {
    if cmp -s "$LH_TARGET" "$WORK_DIR/lh.php" && cmp -s "$LOCALTX_TARGET" "$WORK_DIR/localtx.php" && [[ -f "$HELPER_TARGET" ]] && cmp -s "$HELPER_SOURCE" "$HELPER_TARGET" && [[ -f "$HISTORY_CAPTURE_TARGET" ]] && cmp -s "$HISTORY_CAPTURE_SOURCE" "$HISTORY_CAPTURE_TARGET" && [[ -f "$HISTORY_SERVICE_TARGET" ]] && cmp -s "$HISTORY_SERVICE_SOURCE" "$HISTORY_SERVICE_TARGET" && [[ -f "$HISTORY_PATH_TARGET" ]] && cmp -s "$HISTORY_PATH_SOURCE" "$HISTORY_PATH_TARGET"; then
        printf 'ALREADY MODIFIED: activity mode labels and transition tracking are installed.\n'
    else
        printf 'MODIFICATION READY:\nBefore lh.php:      %s\nAfter lh.php:       %s\nBefore localtx.php: %s\nAfter localtx.php:  %s\n' \
            "$(file_hash "$LH_TARGET")" "$(file_hash "$WORK_DIR/lh.php")" \
            "$(file_hash "$LOCALTX_TARGET")" "$(file_hash "$WORK_DIR/localtx.php")"
    fi
}

run_check() {
    preflight
    [[ -r /var/lib/dvswitch-mode-buttons/current-mode ]] || die 'DVSwitch-Mode-Buttons current-mode state is missing; install and select a mode before using this modification.'
    prepare_candidates
    show_result
    printf 'PASS: supported activity cells and transition-tracker files. No files changed.\n'
}

run_install() {
    preflight
    [[ -r /var/lib/dvswitch-mode-buttons/current-mode ]] || die 'DVSwitch-Mode-Buttons current-mode state is missing; install and select a mode before installing this modification.'
    prepare_candidates
    show_result
    if cmp -s "$LH_TARGET" "$WORK_DIR/lh.php" && cmp -s "$LOCALTX_TARGET" "$WORK_DIR/localtx.php" && [[ -f "$HELPER_TARGET" ]] && cmp -s "$HELPER_SOURCE" "$HELPER_TARGET" && [[ -f "$HISTORY_CAPTURE_TARGET" ]] && cmp -s "$HISTORY_CAPTURE_SOURCE" "$HISTORY_CAPTURE_TARGET" && [[ -f "$HISTORY_SERVICE_TARGET" ]] && cmp -s "$HISTORY_SERVICE_SOURCE" "$HISTORY_SERVICE_TARGET" && [[ -f "$HISTORY_PATH_TARGET" ]] && cmp -s "$HISTORY_PATH_SOURCE" "$HISTORY_PATH_TARGET" && systemctl is-enabled --quiet dvswitch-mods-activity-mode-history.path && systemctl is-active --quiet dvswitch-mods-activity-mode-history.path; then
        printf 'PASS: activity mode labels and transition tracking are already installed. No files changed.\n'
        return
    fi
    if [[ -e "$HELPER_TARGET" ]] && ! grep -qE 'DVSwitch-Mods: dashboard activity network labels helper v[123]' "$HELPER_TARGET"; then
        die "Refusing to replace an unrecognized helper file: $HELPER_TARGET"
    fi
    if [[ -e "$HISTORY_CAPTURE_TARGET" ]] && ! grep -qF 'Record DVSwitch mode transitions for timestamp-accurate activity labels.' "$HISTORY_CAPTURE_TARGET"; then die "Refusing to replace an unrecognized history recorder: $HISTORY_CAPTURE_TARGET"; fi
    if [[ -e "$HISTORY_SERVICE_TARGET" ]] && ! grep -qF 'Record DVSwitch mode transitions for dashboard activity labels' "$HISTORY_SERVICE_TARGET"; then die "Refusing to replace an unrecognized systemd service: $HISTORY_SERVICE_TARGET"; fi
    if [[ -e "$HISTORY_PATH_TARGET" ]] && ! grep -qF 'Watch DVSwitch mode state for dashboard activity history' "$HISTORY_PATH_TARGET"; then die "Refusing to replace an unrecognized systemd path: $HISTORY_PATH_TARGET"; fi
    . "$TRANSACTION_LIBRARY"
    dvsm_transaction_begin "$BACKUP_ROOT"
    INSTALL_ACTIVE=1
    systemctl is-enabled --quiet dvswitch-mods-activity-mode-history.path && TRACKER_WAS_ENABLED=1 || true
    if ! cmp -s "$LH_TARGET" "$WORK_DIR/lh.php"; then
        dvsm_backup_file "$LH_TARGET"
        dvsm_install_candidate "$WORK_DIR/lh.php" "$LH_TARGET"
    fi
    if ! cmp -s "$LOCALTX_TARGET" "$WORK_DIR/localtx.php"; then
        dvsm_backup_file "$LOCALTX_TARGET"
        dvsm_install_candidate "$WORK_DIR/localtx.php" "$LOCALTX_TARGET"
    fi
    if [[ ! -e "$HELPER_TARGET" ]]; then
        dvsm_record_absent_file "$HELPER_TARGET"
        dvsm_install_new_candidate "$HELPER_SOURCE" "$HELPER_TARGET" root root 0644
    elif ! cmp -s "$HELPER_SOURCE" "$HELPER_TARGET"; then
        dvsm_backup_file "$HELPER_TARGET"
        dvsm_install_candidate "$HELPER_SOURCE" "$HELPER_TARGET"
    fi
    install_managed_file "$HISTORY_CAPTURE_SOURCE" "$HISTORY_CAPTURE_TARGET" 'Record DVSwitch mode transitions for timestamp-accurate activity labels.' root root 0755
    install_managed_file "$HISTORY_SERVICE_SOURCE" "$HISTORY_SERVICE_TARGET" 'Record DVSwitch mode transitions for dashboard activity labels' root root 0644
    install_managed_file "$HISTORY_PATH_SOURCE" "$HISTORY_PATH_TARGET" 'Watch DVSwitch mode state for dashboard activity history' root root 0644
    cmp -s "$WORK_DIR/lh.php" "$LH_TARGET"
    cmp -s "$WORK_DIR/localtx.php" "$LOCALTX_TARGET"
    cmp -s "$HELPER_SOURCE" "$HELPER_TARGET"
    php -l "$LH_TARGET" >/dev/null
    php -l "$LOCALTX_TARGET" >/dev/null
    php -l "$HELPER_TARGET" >/dev/null
    systemctl is-active --quiet apache2 || die 'apache2 is not active.'
    systemctl daemon-reload
    systemctl enable --now dvswitch-mods-activity-mode-history.path
    systemctl start dvswitch-mods-activity-mode-history.service
    systemctl is-active --quiet dvswitch-mods-activity-mode-history.path || die 'Activity mode history watcher is not active.'
    [[ -r /var/lib/dvswitch-mods/activity-mode-history.tsv ]] || die 'Activity mode history was not initialized.'
    INSTALL_ACTIVE=0
    printf 'PASS: activity mode labels and per-event transition tracking installed atomically.\nBackup: %s\nHistory: /var/lib/dvswitch-mods/activity-mode-history.tsv\n' "$DVSM_TRANSACTION_DIR"
}

install_managed_file() {
    local source=$1 target=$2 marker=$3 owner=$4 group=$5 mode=$6
    if [[ -e "$target" ]]; then
        if cmp -s "$source" "$target"; then return; fi
        grep -qF "$marker" "$target" || die "Refusing to replace an unrecognized managed file: $target"
        dvsm_backup_file "$target"
        dvsm_install_candidate "$source" "$target"
    else
        dvsm_record_absent_file "$target"
        dvsm_install_new_candidate "$source" "$target" "$owner" "$group" "$mode"
    fi
}

run_restore() {
    local name=$1
    preflight
    [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $name"
    local directory="$BACKUP_ROOT/$name"
    require_regular "$directory/MANIFEST"
    awk -F '\t' -v lh="$LH_TARGET" -v localtx="$LOCALTX_TARGET" -v helper="$HELPER_TARGET" -v capture="$HISTORY_CAPTURE_TARGET" -v service="$HISTORY_SERVICE_TARGET" -v path="$HISTORY_PATH_TARGET" '
        NF != 3 || ($1 != "0" && $1 != "1") || ($2 != lh && $2 != localtx && $2 != helper && $2 != capture && $2 != service && $2 != path) { bad=1 }
        { seen[$2]++ }
        END { if (NR < 1 || NR > 6) bad=1; for (target in seen) if (seen[target] != 1) bad=1; exit bad }
    ' "$directory/MANIFEST" || die 'Backup manifest is not a supported activity-mode-label backup.'
    . "$TRANSACTION_LIBRARY"
    systemctl disable --now dvswitch-mods-activity-mode-history.path >/dev/null 2>&1 || true
    systemctl stop dvswitch-mods-activity-mode-history.service >/dev/null 2>&1 || true
    dvsm_restore_backup_set "$directory"
    systemctl daemon-reload
    if [[ -f "$HISTORY_PATH_TARGET" ]]; then
        systemctl enable --now dvswitch-mods-activity-mode-history.path
        systemctl start dvswitch-mods-activity-mode-history.service
    fi
    php -l "$LH_TARGET" >/dev/null
    php -l "$LOCALTX_TARGET" >/dev/null
    [[ ! -f "$HELPER_TARGET" ]] || php -l "$HELPER_TARGET" >/dev/null
    systemctl is-active --quiet apache2 || die 'apache2 is not active.'
    [[ ! -f "$HISTORY_PATH_TARGET" ]] || systemctl is-active --quiet dvswitch-mods-activity-mode-history.path || die 'Activity mode history watcher is not active after restore.'
    printf 'PASS: activity mode labels restored from %s.\n' "$name"
}

case ${1:-} in
    --check) [[ $# -eq 1 ]] || { usage >&2; exit 2; }; run_check ;;
    --install) [[ $# -eq 1 ]] || { usage >&2; exit 2; }; run_install ;;
    --restore) [[ $# -eq 2 ]] || { usage >&2; exit 2; }; run_restore "$2" ;;
    *) usage >&2; exit 2 ;;
esac

cleanup
trap - EXIT INT TERM HUP
