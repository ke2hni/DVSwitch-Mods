#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Label received Gateway Activity DMR rows from timestamped BM/TGIF selections.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly LH_TARGET="/usr/share/dvswitch/include/lh.php"
readonly LOCALTX_TARGET="/usr/share/dvswitch/include/localtx.php"
readonly FUNCTIONS_TARGET="/usr/share/dvswitch/include/functions.php"
readonly HELPER_TARGET="/usr/share/dvswitch/include/dvswitch_mods_activity_mode.php"
readonly HELPER_SOURCE="$SCRIPT_DIR/lib/dvswitch_mods_activity_mode.php"
readonly LEGACY_CAPTURE_TARGET="/usr/local/sbin/dvswitch-mods-activity-mode-history"
readonly NETWORK_WRITER_TARGET="/usr/local/sbin/dvswitch-mods-record-dmr-network"
readonly NETWORK_WRITER_SOURCE="$SCRIPT_DIR/lib/dvswitch_mods_dmr_network_history.py"
readonly HISTORY_SERVICE_TARGET="/etc/systemd/system/dvswitch-mods-activity-mode-history.service"
readonly HISTORY_SERVICE_SOURCE="$SCRIPT_DIR/systemd/dvswitch-mods-activity-mode-history.service"
readonly HISTORY_PATH_TARGET="/etc/systemd/system/dvswitch-mods-activity-mode-history.path"
readonly HISTORY_PATH_SOURCE="$SCRIPT_DIR/systemd/dvswitch-mods-activity-mode-history.path"
readonly PATCHER="$SCRIPT_DIR/lib/patch_dashboard_activity_modes.py"
readonly TRANSACTION_LIBRARY="$SCRIPT_DIR/lib/transaction.sh"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-activity-modes"

WORK_DIR=""
INSTALL_ACTIVE=0
TRACKER_PATH_WAS_ENABLED=0
TRACKER_SERVICE_WAS_ENABLED=0

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
require_regular() { [[ -f "$1" && ! -L "$1" ]] || die "Required regular file not found: $1"; }
file_hash() { sha256sum "$1" | awk '{print $1}'; }
usage() { printf 'Gateway Activity DMR network labels %s\nUsage: sudo %s {--check|--install|--restore BACKUP-NAME}\n' "$SCRIPT_VERSION" "$(basename "$0")"; }

rollback() {
    local status=$?
    if (( INSTALL_ACTIVE )); then
        systemctl disable --now dvswitch-mods-activity-mode-history.path >/dev/null 2>&1 || true
        systemctl disable dvswitch-mods-activity-mode-history.service >/dev/null 2>&1 || true
        systemctl stop dvswitch-mods-activity-mode-history.service >/dev/null 2>&1 || true
        systemctl daemon-reload >/dev/null 2>&1 || true
        dvsm_transaction_rollback || true
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl reset-failed dvswitch-mods-activity-mode-history.path dvswitch-mods-activity-mode-history.service >/dev/null 2>&1 || true
        if (( TRACKER_SERVICE_WAS_ENABLED )); then systemctl enable dvswitch-mods-activity-mode-history.service >/dev/null 2>&1 || true; fi
        if (( TRACKER_PATH_WAS_ENABLED )); then systemctl enable --now dvswitch-mods-activity-mode-history.path >/dev/null 2>&1 || true; fi
    fi
    cleanup
    exit "$status"
}
trap rollback EXIT INT TERM HUP

preflight() {
    [[ $EUID -eq 0 ]] || die 'Run this command with sudo.'
    command -v python3 >/dev/null || die 'python3 is required.'
    command -v php >/dev/null || die 'php is required.'
    command -v systemctl >/dev/null || die 'systemd is required for bridge-configuration change detection.'
    for path in "$LH_TARGET" "$LOCALTX_TARGET" "$FUNCTIONS_TARGET" "$HELPER_SOURCE" "$NETWORK_WRITER_SOURCE" "$HISTORY_SERVICE_SOURCE" "$HISTORY_PATH_SOURCE" "$PATCHER" "$TRANSACTION_LIBRARY"; do require_regular "$path"; done
    for path in "$HELPER_TARGET" "$LEGACY_CAPTURE_TARGET" "$NETWORK_WRITER_TARGET" "$HISTORY_SERVICE_TARGET" "$HISTORY_PATH_TARGET"; do
        [[ ! -e "$path" || -f "$path" && ! -L "$path" ]] || die "Refusing unsupported non-regular target: $path"
    done
}

prepare_candidates() {
    WORK_DIR=$(mktemp -d /tmp/dvswitch-activity-modes.XXXXXX)
    cp -- "$FUNCTIONS_TARGET" "$WORK_DIR/functions.php"
    cp -- "$LH_TARGET" "$WORK_DIR/lh.php"
    cp -- "$LOCALTX_TARGET" "$WORK_DIR/localtx.php"
    python3 "$PATCHER" --functions "$WORK_DIR/functions.php" --lh "$WORK_DIR/lh.php" --localtx "$WORK_DIR/localtx.php"
    php -l "$WORK_DIR/functions.php" >/dev/null || die 'MMDVM log parser PHP syntax validation failed.'
    php -l "$WORK_DIR/lh.php" >/dev/null || die 'Gateway Activity PHP syntax validation failed.'
    php -l "$WORK_DIR/localtx.php" >/dev/null || die 'Local Activity legacy cleanup PHP syntax validation failed.'
    php -l "$HELPER_SOURCE" >/dev/null || die 'DMR network label helper PHP syntax validation failed.'
    python3 -c 'from pathlib import Path; compile(Path(__import__("sys").argv[1]).read_text(), __import__("sys").argv[1], "exec")' "$NETWORK_WRITER_SOURCE" || die 'DMR network history writer Python syntax validation failed.'
    local functions_hash lh_hash localtx_hash
    functions_hash=$(file_hash "$WORK_DIR/functions.php")
    lh_hash=$(file_hash "$WORK_DIR/lh.php")
    localtx_hash=$(file_hash "$WORK_DIR/localtx.php")
    python3 "$PATCHER" --functions "$WORK_DIR/functions.php" --lh "$WORK_DIR/lh.php" --localtx "$WORK_DIR/localtx.php"
    [[ "$functions_hash" == "$(file_hash "$WORK_DIR/functions.php")" && "$lh_hash" == "$(file_hash "$WORK_DIR/lh.php")" && "$localtx_hash" == "$(file_hash "$WORK_DIR/localtx.php")" ]] || die 'Dashboard activity patch is not idempotent.'
}

is_installed() {
    cmp -s "$FUNCTIONS_TARGET" "$WORK_DIR/functions.php" &&
    cmp -s "$LH_TARGET" "$WORK_DIR/lh.php" &&
    cmp -s "$LOCALTX_TARGET" "$WORK_DIR/localtx.php" &&
    [[ -f "$HELPER_TARGET" ]] && cmp -s "$HELPER_SOURCE" "$HELPER_TARGET" &&
    [[ -f "$NETWORK_WRITER_TARGET" ]] && cmp -s "$NETWORK_WRITER_SOURCE" "$NETWORK_WRITER_TARGET" &&
    [[ ! -e "$LEGACY_CAPTURE_TARGET" ]] &&
    [[ -f "$HISTORY_SERVICE_TARGET" ]] && cmp -s "$HISTORY_SERVICE_SOURCE" "$HISTORY_SERVICE_TARGET" &&
    [[ -f "$HISTORY_PATH_TARGET" ]] && cmp -s "$HISTORY_PATH_SOURCE" "$HISTORY_PATH_TARGET" &&
    systemctl is-enabled --quiet dvswitch-mods-activity-mode-history.path &&
    systemctl is-active --quiet dvswitch-mods-activity-mode-history.path
}

show_result() {
    if is_installed; then
        printf 'ALREADY MODIFIED: Gateway Activity DMR rows use the timestamped BM/TGIF selection log.\n'
    else
        printf 'MODIFICATION READY:\nBefore functions.php: %s\nAfter functions.php:  %s\nBefore lh.php:        %s\nAfter lh.php:         %s\n' \
            "$(file_hash "$FUNCTIONS_TARGET")" "$(file_hash "$WORK_DIR/functions.php")" \
            "$(file_hash "$LH_TARGET")" "$(file_hash "$WORK_DIR/lh.php")"
        if cmp -s "$LOCALTX_TARGET" "$WORK_DIR/localtx.php"; then
            printf 'Local Activity: unchanged\n'
        else
            printf 'Local Activity: previous experimental label wrapper will be removed\n'
        fi
        if [[ -x /usr/local/sbin/dvswitch-mode-buttons ]]; then
            printf 'Mode Buttons: detected; its optional history hook will be available after upgrade to a compatible release.\n'
        else
            printf 'Mode Buttons: not installed; Mods will detect BM/TGIF changes from MMDVM_Bridge.ini.\n'
        fi
    fi
}

run_check() {
    preflight
    prepare_candidates
    show_result
    printf 'PASS: supported Gateway Activity and MMDVM log parser structure. No files changed.\n'
}

install_candidate() {
    local source=$1 target=$2 owner=${3:-root} group=${4:-root} mode=${5:-0644}
    if [[ -e "$target" ]]; then
        if cmp -s "$source" "$target"; then return; fi
        dvsm_backup_file "$target"
        dvsm_install_candidate "$source" "$target"
    else
        dvsm_record_absent_file "$target"
        dvsm_install_new_candidate "$source" "$target" "$owner" "$group" "$mode"
    fi
}

install_managed_file() {
    local source=$1 target=$2 marker=$3 owner=$4 group=$5 mode=$6
    if [[ -e "$target" ]]; then
        if cmp -s "$source" "$target"; then return; fi
        case "$target" in
            "$HELPER_TARGET")
                grep -qE 'DVSwitch-Mods: (dashboard activity network labels helper v[123]|DMR network activity labels v1)' "$target" || die "Refusing to replace an unrecognized managed file: $target" ;;
            "$HISTORY_SERVICE_TARGET")
                grep -qE 'Record DVSwitch mode transitions for dashboard activity labels|Record the selected BM/TGIF network for Gateway Activity' "$target" || die "Refusing to replace an unrecognized managed file: $target" ;;
            "$HISTORY_PATH_TARGET")
                grep -qE 'Watch DVSwitch mode state for dashboard activity history|Watch MMDVM_Bridge DMR network selection for Gateway Activity labels' "$target" || die "Refusing to replace an unrecognized managed file: $target" ;;
            *) grep -qF "$marker" "$target" || die "Refusing to replace an unrecognized managed file: $target" ;;
        esac
        dvsm_backup_file "$target"
        dvsm_install_candidate "$source" "$target"
    else
        dvsm_record_absent_file "$target"
        dvsm_install_new_candidate "$source" "$target" "$owner" "$group" "$mode"
    fi
}

run_install() {
    preflight
    prepare_candidates
    show_result
    if is_installed; then
        printf 'PASS: Gateway Activity DMR network labels are already installed. No files changed.\n'
        return
    fi
    if [[ -e "$HELPER_TARGET" ]] && ! grep -qE 'DVSwitch-Mods: (dashboard activity network labels helper v[123]|DMR network activity labels v1)' "$HELPER_TARGET"; then
        die "Refusing to replace an unrecognized activity helper: $HELPER_TARGET"
    fi
    if [[ -e "$NETWORK_WRITER_TARGET" ]] && ! grep -qF 'Record timestamped BM/TGIF selections for Gateway Activity labels.' "$NETWORK_WRITER_TARGET"; then
        die "Refusing to replace an unrecognized DMR network history writer: $NETWORK_WRITER_TARGET"
    fi
    if [[ -e "$LEGACY_CAPTURE_TARGET" ]] && ! grep -qF 'Record DVSwitch mode transitions for timestamp-accurate activity labels.' "$LEGACY_CAPTURE_TARGET"; then
        die "Refusing to remove an unrecognized legacy history recorder: $LEGACY_CAPTURE_TARGET"
    fi
    if [[ -e "$HISTORY_SERVICE_TARGET" ]] && ! grep -qE 'Record DVSwitch mode transitions for dashboard activity labels|Record the selected BM/TGIF network for Gateway Activity' "$HISTORY_SERVICE_TARGET"; then
        die "Refusing to replace an unrecognized activity history service: $HISTORY_SERVICE_TARGET"
    fi
    if [[ -e "$HISTORY_PATH_TARGET" ]] && ! grep -qE 'Watch DVSwitch mode state for dashboard activity history|Watch MMDVM_Bridge DMR network selection for Gateway Activity labels' "$HISTORY_PATH_TARGET"; then
        die "Refusing to replace an unrecognized activity history path: $HISTORY_PATH_TARGET"
    fi

    . "$TRANSACTION_LIBRARY"
    dvsm_transaction_begin "$BACKUP_ROOT"
    INSTALL_ACTIVE=1
    systemctl is-enabled --quiet dvswitch-mods-activity-mode-history.path && TRACKER_PATH_WAS_ENABLED=1 || true
    systemctl is-enabled --quiet dvswitch-mods-activity-mode-history.service && TRACKER_SERVICE_WAS_ENABLED=1 || true
    systemctl disable --now dvswitch-mods-activity-mode-history.path >/dev/null 2>&1 || true
    systemctl disable dvswitch-mods-activity-mode-history.service >/dev/null 2>&1 || true
    systemctl stop dvswitch-mods-activity-mode-history.service >/dev/null 2>&1 || true

    install_candidate "$WORK_DIR/functions.php" "$FUNCTIONS_TARGET"
    install_candidate "$WORK_DIR/lh.php" "$LH_TARGET"
    install_candidate "$WORK_DIR/localtx.php" "$LOCALTX_TARGET"
    install_managed_file "$HELPER_SOURCE" "$HELPER_TARGET" 'DVSwitch-Mods: DMR network activity labels v1' root root 0644
    install_managed_file "$NETWORK_WRITER_SOURCE" "$NETWORK_WRITER_TARGET" 'Record timestamped BM/TGIF selections for Gateway Activity labels.' root root 0755
    if [[ -e "$LEGACY_CAPTURE_TARGET" ]]; then
        dvsm_backup_file "$LEGACY_CAPTURE_TARGET"
        rm -f -- "$LEGACY_CAPTURE_TARGET"
    fi
    install_managed_file "$HISTORY_SERVICE_SOURCE" "$HISTORY_SERVICE_TARGET" 'Record DVSwitch mode transitions for dashboard activity labels' root root 0644
    install_managed_file "$HISTORY_PATH_SOURCE" "$HISTORY_PATH_TARGET" 'Watch MMDVM_Bridge DMR network selection for Gateway Activity labels' root root 0644

    php -l "$FUNCTIONS_TARGET" >/dev/null
    php -l "$LH_TARGET" >/dev/null
    php -l "$LOCALTX_TARGET" >/dev/null
    php -l "$HELPER_TARGET" >/dev/null
    systemctl is-active --quiet apache2 || die 'apache2 is not active.'
    "$NETWORK_WRITER_TARGET" --seed-current
    systemctl daemon-reload
    # A newly installed unit may not have a failed-state record yet; in that
    # case systemctl reset-failed can report "Unit not loaded". Clearing an
    # old failure is helpful, but must not block first-time installation.
    systemctl reset-failed dvswitch-mods-activity-mode-history.path dvswitch-mods-activity-mode-history.service >/dev/null 2>&1 || true
    systemctl enable --now dvswitch-mods-activity-mode-history.path
    systemctl is-active --quiet dvswitch-mods-activity-mode-history.path || die 'DMR network history watcher is not active.'
    INSTALL_ACTIVE=0
    printf 'PASS: Gateway Activity DMR network labels installed atomically.\nBackup: %s\nHistory: /var/lib/dvswitch-mods/dmr-network-history.tsv\n' "$DVSM_TRANSACTION_DIR"
}

run_restore() {
    local name=$1 directory
    [[ $EUID -eq 0 ]] || die 'Run this command with sudo.'
    command -v systemctl >/dev/null || die 'systemd is required to restore this component.'
    require_regular "$TRANSACTION_LIBRARY"
    [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $name"
    directory="$BACKUP_ROOT/$name"
    require_regular "$directory/MANIFEST"
    awk -F '\t' -v lh="$LH_TARGET" -v localtx="$LOCALTX_TARGET" -v functions="$FUNCTIONS_TARGET" -v helper="$HELPER_TARGET" -v legacy="$LEGACY_CAPTURE_TARGET" -v writer="$NETWORK_WRITER_TARGET" -v service="$HISTORY_SERVICE_TARGET" -v path="$HISTORY_PATH_TARGET" '
        NF != 3 || ($1 != "0" && $1 != "1") || ($2 != lh && $2 != localtx && $2 != functions && $2 != helper && $2 != legacy && $2 != writer && $2 != service && $2 != path) { bad=1 }
        { seen[$2]++ }
        END { if (NR < 1 || NR > 8) bad=1; for (target in seen) if (seen[target] != 1) bad=1; exit bad }
    ' "$directory/MANIFEST" || die 'Backup manifest is not a supported activity-mode-label backup.'
    systemctl disable --now dvswitch-mods-activity-mode-history.path >/dev/null 2>&1 || true
    systemctl disable dvswitch-mods-activity-mode-history.service >/dev/null 2>&1 || true
    systemctl stop dvswitch-mods-activity-mode-history.service >/dev/null 2>&1 || true
    . "$TRANSACTION_LIBRARY"
    dvsm_restore_backup_set "$directory"
    systemctl daemon-reload
    if [[ -f "$HISTORY_SERVICE_TARGET" ]] && grep -q '^WantedBy=multi-user.target$' "$HISTORY_SERVICE_TARGET" && grep -q 'ExecStart=/usr/local/sbin/dvswitch-mods-activity-mode-history$' "$HISTORY_SERVICE_TARGET"; then
        systemctl enable dvswitch-mods-activity-mode-history.service
        systemctl start dvswitch-mods-activity-mode-history.service
    fi
    if [[ -f "$HISTORY_PATH_TARGET" ]] && grep -q '^WantedBy=multi-user.target$' "$HISTORY_PATH_TARGET"; then
        systemctl enable --now dvswitch-mods-activity-mode-history.path
    fi
    command -v php >/dev/null || die 'php is required to validate restored dashboard files.'
    php -l "$LH_TARGET" >/dev/null
    php -l "$FUNCTIONS_TARGET" >/dev/null
    php -l "$LOCALTX_TARGET" >/dev/null
    [[ ! -f "$HELPER_TARGET" ]] || php -l "$HELPER_TARGET" >/dev/null
    systemctl is-active --quiet apache2 || die 'apache2 is not active.'
    if [[ -f "$HISTORY_PATH_TARGET" && -f "$HISTORY_SERVICE_TARGET" ]] && grep -q 'ExecStart=/usr/local/sbin/dvswitch-mods-record-dmr-network --current' "$HISTORY_SERVICE_TARGET"; then
        systemctl is-active --quiet dvswitch-mods-activity-mode-history.path || die 'DMR network history watcher is not active after restore.'
    fi
    printf 'PASS: Gateway Activity DMR network labels restored from %s.\n' "$name"
}

case ${1:-} in
    --check) [[ $# -eq 1 ]] || { usage >&2; exit 2; }; run_check ;;
    --install) [[ $# -eq 1 ]] || { usage >&2; exit 2; }; run_install ;;
    --restore) [[ $# -eq 2 ]] || { usage >&2; exit 2; }; run_restore "$2" ;;
    *) usage >&2; exit 2 ;;
esac

cleanup
trap - EXIT INT TERM HUP
