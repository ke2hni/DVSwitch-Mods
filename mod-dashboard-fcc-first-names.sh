#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="1.2.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PATCHER="$SCRIPT_DIR/lib/patch_dashboard_first_names.py"
readonly BUILDER="$SCRIPT_DIR/lib/build_fcc_first_names.py"
readonly HELPER_SOURCE="$SCRIPT_DIR/lib/dvswitch_mods_fcc_first_names.php"
readonly TRANSACTION_LIBRARY="$SCRIPT_DIR/lib/transaction.sh"
readonly UPDATER_SOURCE="$SCRIPT_DIR/lib/dvswitch_fcc_first_names_update.sh"
readonly SERVICE_SOURCE="$SCRIPT_DIR/systemd/dvswitch-fcc-first-names-update.service"
readonly TIMER_SOURCE="$SCRIPT_DIR/systemd/dvswitch-fcc-first-names-update.timer"
readonly LH_TARGET="/usr/share/dvswitch/include/lh.php"
readonly LOCALTX_TARGET="/usr/share/dvswitch/include/localtx.php"
readonly HELPER_TARGET="/usr/share/dvswitch/include/dvswitch_mods_fcc_first_names.php"
readonly DATABASE_TARGET="/var/lib/mmdvm/dvswitch-mods-fcc-first-names.dat"
readonly UPDATER_TARGET="/usr/local/sbin/dvswitch-fcc-first-names-update"
readonly INSTALLED_LIBRARY_DIR="/usr/local/lib/dvswitch-mods"
readonly BUILDER_TARGET="$INSTALLED_LIBRARY_DIR/build_fcc_first_names.py"
readonly PATCHER_TARGET="$INSTALLED_LIBRARY_DIR/patch_dashboard_first_names.py"
readonly TRANSACTION_TARGET="$INSTALLED_LIBRARY_DIR/transaction.sh"
readonly SERVICE_TARGET="/etc/systemd/system/dvswitch-fcc-first-names-update.service"
readonly TIMER_TARGET="/etc/systemd/system/dvswitch-fcc-first-names-update.timer"
readonly TIMER_UNIT="dvswitch-fcc-first-names-update.timer"
readonly PREVIOUS_TIMER_SHA256_V110="5624772150bd1d71f231417b23cd0e48eccd624591523e7f1c0ef9ffae1dea99"
readonly PREVIOUS_TIMER_SHA256_V112="5d929156ef445c6e3d0c7ee32609f8c2e9cf29042c4cd13b161cae7215f76974"
readonly PREVIOUS_UPDATER_SHA256_V113="cccb47f9f0dec56556f239372fc722dd83623ab8b65f679da1c1eaa685a738bc"
readonly BUILDER_SHA256_V113="d4831315dfdd133174a415fe288c6c3c8d49852336a0dcc196b4b0a2130e4ae2"
readonly TRANSACTION_SHA256_V113="13d743d6065f88888725a1aefe98c8d4ad957974ec5cd991a52ff20ac44a6532"
readonly SERVICE_SHA256_V113="78c0b1da92560f27aae8db1faa3630498055c3e48663f709f9217463c7eb0267"
readonly TIMER_SHA256_V113="28e8ec01752c230132848f5891a504194b1dadd6035580b355ad49dee5d05cf3"
readonly WORK_ROOT="/var/lib/mmdvm"
readonly FCC_URL="https://data.fcc.gov/download/pub/uls/complete/l_amat.zip"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-fcc-first-names"
readonly DASHBOARD_URL="https://127.0.0.1/dvswitch/"

WORK_DIR=""
INSTALL_ACTIVE=0
TIMER_CHANGED=0

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
usage() { printf 'FCC first-name dashboard modification %s\nUsage: sudo %s {--check|--install|--update|--remove-updater|--restore BACKUP-NAME|--uninstall BACKUP-NAME}\n' "$SCRIPT_VERSION" "$(basename "$0")"; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
require_file() { [[ -f "$1" && ! -L "$1" ]] || die "Required regular non-symlink file not found: $1"; }
file_hash() { sha256sum "$1" | awk '{print $1}'; }

on_error() {
    local line=$1 status=$2
    trap - ERR
    set +e
    printf 'ERROR: failed near line %s (status %s).\n' "$line" "$status" >&2
    if [[ $INSTALL_ACTIVE -eq 1 ]]; then
        dvsm_transaction_rollback >&2 || printf 'ERROR: automatic rollback failed; use the protected backup.\n' >&2
        systemctl daemon-reload >/dev/null 2>&1 || true
        if [[ -f "$TIMER_TARGET" && ! -L "$TIMER_TARGET" ]]; then systemctl enable --now "$TIMER_UNIT" >/dev/null 2>&1 || true
        else systemctl disable --now "$TIMER_UNIT" >/dev/null 2>&1 || true; fi
        systemctl reload apache2.service >/dev/null 2>&1 || true
    fi
    cleanup
    exit "$status"
}
trap 'on_error $LINENO $?' ERR
trap cleanup EXIT

check_platform() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this modification with sudo."
    . /etc/os-release
    [[ ${ID:-} == debian ]] || die "Unsupported OS: ${ID:-unknown}"
    case "${VERSION_ID:-}" in 12|13) ;; *) die "Unsupported Debian version: ${VERSION_ID:-unknown}" ;; esac
}

dashboard_health() {
    systemctl is-active --quiet apache2.service || return 1
    [[ $(curl -ksS -o /dev/null -w '%{http_code}' --max-time 15 "$DASHBOARD_URL") == 200 ]]
}

preflight() {
    check_platform
    for command in awk chmod chown cmp cp curl date install mktemp mv php python3 rm sha256sum stat systemctl; do require_command "$command"; done
    require_file "$PATCHER"; require_file "$BUILDER"; require_file "$HELPER_SOURCE"; require_file "$TRANSACTION_LIBRARY"
    require_file "$UPDATER_SOURCE"; require_file "$SERVICE_SOURCE"; require_file "$TIMER_SOURCE"
    require_file "$LH_TARGET"; require_file "$LOCALTX_TARGET"
    php -l "$LH_TARGET" >/dev/null; php -l "$LOCALTX_TARGET" >/dev/null; php -l "$HELPER_SOURCE" >/dev/null
    dashboard_health || die "Apache or the HTTPS dashboard is not healthy."
}

updater_targets() {
    printf '%s\n' "$UPDATER_TARGET" "$BUILDER_TARGET" "$PATCHER_TARGET" "$TRANSACTION_TARGET" "$SERVICE_TARGET" "$TIMER_TARGET"
}

updater_state() {
    local present=0 missing=0 target
    while IFS= read -r target; do
        if [[ -f "$target" && ! -L "$target" ]]; then present=$((present + 1))
        elif [[ ! -e "$target" && ! -L "$target" ]]; then missing=$((missing + 1))
        else die "Refusing unsupported updater target state: $target"; fi
    done < <(updater_targets)
    if [[ $present -eq 0 ]]; then printf 'absent'
    elif [[ $present -eq 5 && $missing -eq 1 && ! -e "$PATCHER_TARGET" && ! -L "$PATCHER_TARGET" ]]; then printf 'legacy'
    elif [[ $missing -eq 0 ]]; then printf 'present'
    else die "FCC updater installation is incomplete ($present present, $missing missing)."; fi
}

updater_release_state() {
    local state
    state=$(updater_state)
    [[ "$state" != absent ]] || { printf 'absent'; return; }
    if [[ "$state" == legacy ]]; then
        [[ "$(file_hash "$UPDATER_TARGET")" == "$PREVIOUS_UPDATER_SHA256_V113" ]] || die "Installed legacy FCC updater has an unsupported checksum."
        [[ "$(file_hash "$BUILDER_TARGET")" == "$BUILDER_SHA256_V113" ]] || die "Installed legacy FCC builder has an unsupported checksum."
        [[ "$(file_hash "$TRANSACTION_TARGET")" == "$TRANSACTION_SHA256_V113" ]] || die "Installed legacy FCC transaction helper has an unsupported checksum."
        [[ "$(file_hash "$SERVICE_TARGET")" == "$SERVICE_SHA256_V113" ]] || die "Installed legacy FCC service has an unsupported checksum."
        local legacy_timer_hash
        legacy_timer_hash=$(file_hash "$TIMER_TARGET")
        case "$legacy_timer_hash" in
            "$PREVIOUS_TIMER_SHA256_V110"|"$PREVIOUS_TIMER_SHA256_V112"|"$TIMER_SHA256_V113") ;;
            *) die "Installed legacy FCC timer has an unsupported checksum." ;;
        esac
        [[ "$(stat -c '%U:%G:%a' "$UPDATER_TARGET")" == root:root:755 ]] || die "Incorrect legacy updater ownership or mode."
        for target in "$BUILDER_TARGET" "$TRANSACTION_TARGET" "$SERVICE_TARGET" "$TIMER_TARGET"; do
            [[ "$(stat -c '%U:%G:%a' "$target")" == root:root:644 ]] || die "Incorrect ownership or mode: $target"
        done
        systemctl is-enabled --quiet "$TIMER_UNIT" || die "FCC weekly update timer is not enabled."
        systemctl is-active --quiet "$TIMER_UNIT" || die "FCC weekly update timer is not active."
        printf 'upgradeable'
        return
    fi
    cmp -s "$UPDATER_SOURCE" "$UPDATER_TARGET" || die "Installed FCC updater does not match this release."
    cmp -s "$BUILDER" "$BUILDER_TARGET" || die "Installed FCC builder does not match this release."
    cmp -s "$TRANSACTION_LIBRARY" "$TRANSACTION_TARGET" || die "Installed FCC transaction helper does not match this release."
    cmp -s "$SERVICE_SOURCE" "$SERVICE_TARGET" || die "Installed FCC systemd service does not match this release."
    [[ "$(stat -c '%U:%G:%a' "$UPDATER_TARGET")" == root:root:755 ]] || die "Incorrect updater ownership or mode."
    for target in "$BUILDER_TARGET" "$TRANSACTION_TARGET" "$SERVICE_TARGET" "$TIMER_TARGET"; do
        [[ "$(stat -c '%U:%G:%a' "$target")" == root:root:644 ]] || die "Incorrect ownership or mode: $target"
    done
    systemctl is-enabled --quiet "$TIMER_UNIT" || die "FCC weekly update timer is not enabled."
    systemctl is-active --quiet "$TIMER_UNIT" || die "FCC weekly update timer is not active."
    if cmp -s "$TIMER_SOURCE" "$TIMER_TARGET"; then
        printf 'current'
    else
        local timer_hash
        timer_hash=$(file_hash "$TIMER_TARGET")
        case "$timer_hash" in
            "$PREVIOUS_TIMER_SHA256_V110"|"$PREVIOUS_TIMER_SHA256_V112") printf 'upgradeable' ;;
            *) die "Installed FCC systemd timer has an unsupported checksum: $timer_hash" ;;
        esac
    fi
}

verify_updater_components() {
    [[ "$(updater_release_state)" == current ]] || die "Installed FCC updater requires --install to upgrade it to this release."
}

report_updater_checksums() {
    printf 'Updater SHA256: %s\nBuilder SHA256: %s\nPatcher SHA256: %s\nService SHA256: %s\nTimer SHA256: %s\n' \
        "$(file_hash "$UPDATER_TARGET")" "$(file_hash "$BUILDER_TARGET")" "$(file_hash "$PATCHER_TARGET")" \
        "$(file_hash "$SERVICE_TARGET")" "$(file_hash "$TIMER_TARGET")"
}

stage_updater_component() {
    local source=$1 target=$2 owner=$3 group=$4 mode=$5
    if [[ -f "$target" && ! -L "$target" ]] && cmp -s "$source" "$target" && [[ "$(stat -c '%U:%G:%a' "$target")" == "$owner:$group:${mode#0}" ]]; then return; fi
    backup_target "$target"
    install_one "$source" "$target" "$owner" "$group" "$mode"
    [[ "$target" != "$TIMER_TARGET" ]] || TIMER_CHANGED=1
}

stage_updater_components() {
    install -d -o root -g root -m 0755 "$INSTALLED_LIBRARY_DIR" "$(dirname "$UPDATER_TARGET")" "$(dirname "$SERVICE_TARGET")"
    stage_updater_component "$UPDATER_SOURCE" "$UPDATER_TARGET" root root 0755
    stage_updater_component "$BUILDER" "$BUILDER_TARGET" root root 0644
    stage_updater_component "$PATCHER" "$PATCHER_TARGET" root root 0644
    stage_updater_component "$TRANSACTION_LIBRARY" "$TRANSACTION_TARGET" root root 0644
    stage_updater_component "$SERVICE_SOURCE" "$SERVICE_TARGET" root root 0644
    stage_updater_component "$TIMER_SOURCE" "$TIMER_TARGET" root root 0644
}

prepare_dashboard() {
    [[ -d "$WORK_ROOT" && ! -L "$WORK_ROOT" ]] || die "Required work root is unavailable: $WORK_ROOT"
    [[ -n "$WORK_DIR" ]] || WORK_DIR=$(mktemp -d "$WORK_ROOT/.dvswitch-fcc-firstnames.XXXXXX")
    cp -- "$LH_TARGET" "$WORK_DIR/lh.php"
    cp -- "$LOCALTX_TARGET" "$WORK_DIR/localtx.php"
    python3 "$PATCHER" --lh "$WORK_DIR/lh.php" --localtx "$WORK_DIR/localtx.php"
    php -l "$WORK_DIR/lh.php" >/dev/null; php -l "$WORK_DIR/localtx.php" >/dev/null
    local lh_hash localtx_hash
    lh_hash=$(file_hash "$WORK_DIR/lh.php"); localtx_hash=$(file_hash "$WORK_DIR/localtx.php")
    python3 "$PATCHER" --lh "$WORK_DIR/lh.php" --localtx "$WORK_DIR/localtx.php"
    [[ "$lh_hash" == "$(file_hash "$WORK_DIR/lh.php")" && "$localtx_hash" == "$(file_hash "$WORK_DIR/localtx.php")" ]] || die "Dashboard patch is not idempotent."
}

build_database() {
    [[ -d "$WORK_ROOT" && ! -L "$WORK_ROOT" ]] || die "Required work root is unavailable: $WORK_ROOT"
    [[ -n "$WORK_DIR" ]] || WORK_DIR=$(mktemp -d "$WORK_ROOT/.dvswitch-fcc-firstnames.XXXXXX")
    local archive="$WORK_DIR/l_amat.zip"
    printf 'Downloading FCC weekly Amateur Radio Service archive...\n'
    curl --fail --location --silent --show-error --connect-timeout 30 --max-time 900 --retry 2 --output "$archive" "$FCC_URL"
    printf 'Downloaded archive: %s bytes\n' "$(stat -c %s "$archive")"
    python3 "$BUILDER" --archive "$archive" --output "$WORK_DIR/fcc-first-names.dat" >/dev/null
    rm -f -- "$archive"
    printf 'Validated FCC database: %s records, %s bytes\nFCC database SHA256: %s\n' \
        "$(python3 "$BUILDER" --validate "$WORK_DIR/fcc-first-names.dat")" \
        "$(stat -c %s "$WORK_DIR/fcc-first-names.dat")" \
        "$(file_hash "$WORK_DIR/fcc-first-names.dat")"
}

backup_target() {
    local target=$1
    if [[ -f "$target" && ! -L "$target" ]]; then dvsm_backup_file "$target"
    elif [[ ! -e "$target" && ! -L "$target" ]]; then dvsm_record_absent_file "$target"
    else die "Refusing unsupported target state: $target"; fi
}

install_one() {
    local candidate=$1 target=$2 owner=$3 group=$4 mode=$5
    if [[ -f "$target" && ! -L "$target" ]]; then dvsm_install_candidate "$candidate" "$target"
    else install -d -o "$owner" -g "$group" -m 0755 "$(dirname "$target")"; dvsm_install_new_candidate "$candidate" "$target" "$owner" "$group" "$mode"; fi
}

stage_install_component() {
    local source=$1 target=$2 owner=$3 group=$4 mode=$5
    if [[ -f "$target" && ! -L "$target" ]] && cmp -s "$source" "$target" && [[ "$(stat -c '%U:%G:%a' "$target")" == "$owner:$group:${mode#0}" ]]; then return; fi
    backup_target "$target"
    install_one "$source" "$target" "$owner" "$group" "$mode"
}

run_check() {
    preflight; prepare_dashboard
    if cmp -s "$LH_TARGET" "$WORK_DIR/lh.php" && cmp -s "$LOCALTX_TARGET" "$WORK_DIR/localtx.php"; then
        printf 'ALREADY MODIFIED: Gateway and Local Activity FCC first-name columns are installed.\n'
    else
        printf 'MODIFICATION READY:\nBefore lh.php:      %s\nAfter lh.php:       %s\nBefore localtx.php: %s\nAfter localtx.php:  %s\n' "$(file_hash "$LH_TARGET")" "$(file_hash "$WORK_DIR/lh.php")" "$(file_hash "$LOCALTX_TARGET")" "$(file_hash "$WORK_DIR/localtx.php")"
    fi
    if [[ -f "$DATABASE_TARGET" && ! -L "$DATABASE_TARGET" ]]; then
        local database_count database_checksum
        database_count=$(python3 "$BUILDER" --validate "$DATABASE_TARGET")
        database_checksum=$(file_hash "$DATABASE_TARGET")
        printf 'FCC database: %s validated records, %s bytes.\nFCC database SHA256: %s\n' "$database_count" "$(stat -c %s "$DATABASE_TARGET")" "$database_checksum"
    else printf 'FCC database: not installed; --install will download and build it.\n'; fi
    local release_state
    release_state=$(updater_release_state)
    if [[ "$release_state" == current ]]; then
        report_updater_checksums
        printf 'FCC weekly updater: installed, enabled, and active.\n'
    elif [[ "$release_state" == upgradeable ]]; then
        printf 'FCC weekly updater: supported previous release detected; --install will upgrade it.\n'
    else
        printf 'FCC weekly updater: not installed; --install will add it.\n'
    fi
    printf 'PASS: supported activity-table structure. No files changed.\n'
}

run_install() {
    preflight; prepare_dashboard
    if cmp -s "$LH_TARGET" "$WORK_DIR/lh.php" && cmp -s "$LOCALTX_TARGET" "$WORK_DIR/localtx.php" && [[ -f "$HELPER_TARGET" ]] && cmp -s "$HELPER_SOURCE" "$HELPER_TARGET" && [[ -f "$DATABASE_TARGET" ]] && python3 "$BUILDER" --validate "$DATABASE_TARGET" >/dev/null && [[ "$(updater_release_state)" == current ]]; then
        printf 'PASS: FCC first-name dashboard modification is already installed. No files changed.\n'; return
    fi
    local database_ready=0
    if [[ -f "$DATABASE_TARGET" && ! -L "$DATABASE_TARGET" ]] && python3 "$BUILDER" --validate "$DATABASE_TARGET" >/dev/null; then
        database_ready=1
    else
        build_database
    fi
    . "$TRANSACTION_LIBRARY"
    dvsm_transaction_begin "$BACKUP_ROOT"
    INSTALL_ACTIVE=1
    stage_updater_components
    stage_install_component "$WORK_DIR/lh.php" "$LH_TARGET" root root 0644
    stage_install_component "$WORK_DIR/localtx.php" "$LOCALTX_TARGET" root root 0644
    stage_install_component "$HELPER_SOURCE" "$HELPER_TARGET" root root 0644
    if [[ $database_ready -eq 0 ]]; then stage_install_component "$WORK_DIR/fcc-first-names.dat" "$DATABASE_TARGET" root www-data 0644; fi
    php -l "$LH_TARGET" >/dev/null; php -l "$LOCALTX_TARGET" >/dev/null; php -l "$HELPER_TARGET" >/dev/null
    python3 "$BUILDER" --validate "$DATABASE_TARGET" >/dev/null
    systemctl daemon-reload
    if [[ $TIMER_CHANGED -eq 1 ]]; then
        systemctl enable "$TIMER_UNIT"
        systemctl restart "$TIMER_UNIT"
    else
        systemctl enable --now "$TIMER_UNIT"
    fi
    verify_updater_components
    systemctl reload apache2.service; dashboard_health
    INSTALL_ACTIVE=0
    printf 'PASS: FCC first-name dashboard modification installed atomically.\nBackup: %s\n' "$DVSM_TRANSACTION_DIR"
}

run_update() {
    preflight
    verify_updater_components || die "Permanent FCC updater is not installed; run --install first."
    "$UPDATER_TARGET"
}

run_remove_updater() {
    preflight
    if [[ "$(updater_state)" == absent ]]; then printf 'PASS: FCC weekly updater is already removed. No files changed.\n'; return; fi
    updater_release_state >/dev/null
    "$UPDATER_TARGET" --remove-updater
}

uninstall_backup_file() {
    local directory=$1 target=$2 result
    result=$(awk -F '\t' -v wanted="$target" '$1 == "1" && $2 == wanted { print $3 }' "$directory/MANIFEST")
    [[ -n "$result" && "$result" != *$'\n'* && "$result" == "$directory/"* ]] || die "Backup is not a complete original FCC Name installation backup: $target"
    require_file "$result"
    printf '%s' "$result"
}

run_uninstall() {
    preflight
    local name=$1 directory="$BACKUP_ROOT/$1" original_lh original_local target
    [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name."
    [[ -d "$directory" && ! -L "$directory" ]] || die "Backup not found: $name"
    require_file "$directory/MANIFEST"
    original_lh=$(uninstall_backup_file "$directory" "$LH_TARGET")
    original_local=$(uninstall_backup_file "$directory" "$LOCALTX_TARGET")
    [[ -n "$WORK_DIR" ]] || WORK_DIR=$(mktemp -d "$WORK_ROOT/.dvswitch-fcc-firstnames.XXXXXX")
    install -d -m 0700 "$WORK_DIR/original"
    cp -- "$original_lh" "$WORK_DIR/original/lh.php"; cp -- "$original_local" "$WORK_DIR/original/localtx.php"
    python3 "$PATCHER" --lh "$WORK_DIR/original/lh.php" --localtx "$WORK_DIR/original/localtx.php"
    . "$TRANSACTION_LIBRARY"
    dvsm_transaction_begin "$BACKUP_ROOT"
    for target in "$LH_TARGET" "$LOCALTX_TARGET" "$HELPER_TARGET" "$DATABASE_TARGET"; do backup_target "$target"; done
    while IFS= read -r target; do backup_target "$target"; done < <(updater_targets)
    INSTALL_ACTIVE=1
    systemctl disable --now "$TIMER_UNIT" >/dev/null 2>&1 || true
    dvsm_restore_backup_set "$directory"
    rm -f -- "$HELPER_TARGET" "$DATABASE_TARGET"
    while IFS= read -r target; do rm -f -- "$target"; done < <(updater_targets)
    php -l "$LH_TARGET" >/dev/null; php -l "$LOCALTX_TARGET" >/dev/null
    systemctl daemon-reload
    systemctl reload apache2.service; dashboard_health
    INSTALL_ACTIVE=0
    printf 'PASS: FCC first-name dashboard modification and weekly updater uninstalled.\nSafety backup: %s\n' "$DVSM_TRANSACTION_DIR"
}

run_restore() {
    preflight
    local name=$1 directory="$BACKUP_ROOT/$1"
    [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name."
    [[ -d "$directory" && ! -L "$directory" ]] || die "Backup not found: $name"
    . "$TRANSACTION_LIBRARY"
    systemctl disable --now "$TIMER_UNIT" >/dev/null 2>&1 || true
    dvsm_restore_backup_set "$directory"
    if [[ -f "$UPDATER_TARGET" && ! -L "$UPDATER_TARGET" && "$(file_hash "$UPDATER_TARGET")" == "$PREVIOUS_UPDATER_SHA256_V113" ]] && ! awk -F '\t' -v wanted="$PATCHER_TARGET" '$2 == wanted { found=1 } END { exit(found ? 0 : 1) }' "$directory/MANIFEST"; then
        rm -f -- "$PATCHER_TARGET"
    fi
    php -l "$LH_TARGET" >/dev/null; php -l "$LOCALTX_TARGET" >/dev/null
    systemctl daemon-reload
    local restored_updater_state
    restored_updater_state=$(updater_state)
    if [[ "$restored_updater_state" != absent ]]; then systemctl enable --now "$TIMER_UNIT"; updater_release_state >/dev/null; fi
    systemctl reload apache2.service; dashboard_health
    printf 'PASS: FCC first-name dashboard files restored from %s.\n' "$name"
}

case "${1:-}" in
    --check) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_check ;;
    --install) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_install ;;
    --update) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_update ;;
    --remove-updater) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_remove_updater ;;
    --restore) [[ $# -eq 2 ]] || die "--restore requires one backup name."; run_restore "$2" ;;
    --uninstall) [[ $# -eq 2 ]] || die "--uninstall requires the original installation backup name."; run_uninstall "$2" ;;
    --help|-h) usage ;;
    "") usage; exit 2 ;;
    *) die "Unknown option: $1" ;;
esac
