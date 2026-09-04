#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

set -Eeuo pipefail
umask 077

readonly UPDATER_VERSION="1.2.1"
readonly LIBRARY_DIR="/usr/local/lib/dvswitch-mods"
readonly BUILDER="$LIBRARY_DIR/build_fcc_first_names.py"
readonly PATCHER="$LIBRARY_DIR/patch_dashboard_first_names.py"
readonly TRANSACTION_LIBRARY="$LIBRARY_DIR/transaction.sh"
readonly UPDATER_TARGET="/usr/local/sbin/dvswitch-fcc-first-names-update"
readonly SERVICE_TARGET="/etc/systemd/system/dvswitch-fcc-first-names-update.service"
readonly TIMER_TARGET="/etc/systemd/system/dvswitch-fcc-first-names-update.timer"
readonly TIMER_UNIT="dvswitch-fcc-first-names-update.timer"
readonly LH_TARGET="/usr/share/dvswitch/include/lh.php"
readonly LOCALTX_TARGET="/usr/share/dvswitch/include/localtx.php"
readonly HELPER_TARGET="/usr/share/dvswitch/include/dvswitch_mods_fcc_first_names.php"
readonly DATABASE_TARGET="/var/lib/mmdvm/dvswitch-mods-fcc-first-names.dat"
readonly WORK_ROOT="/var/lib/mmdvm"
readonly FCC_URL="https://data.fcc.gov/download/pub/uls/complete/l_amat.zip"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-fcc-first-names"
readonly LOCK_FILE="/run/lock/dvswitch-fcc-first-names-update.lock"
readonly BUILDER_SHA256="d4831315dfdd133174a415fe288c6c3c8d49852336a0dcc196b4b0a2130e4ae2"
readonly PATCHER_SHA256="80ba8c7e998a596ef43a138ab678457b1a5afce61cb1a2396099fac735ef9a4d"
readonly TRANSACTION_SHA256="13d743d6065f88888725a1aefe98c8d4ad957974ec5cd991a52ff20ac44a6532"
readonly HELPER_SHA256="7481c7099b9f7c4f58691052b71535bbe602774e8c0c6f5856341af22c1d09d9"

WORK_DIR=""
INSTALL_ACTIVE=0

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
require_file() { [[ -f "$1" && ! -L "$1" ]] || die "Required regular non-symlink file not found: $1"; }
file_hash() { sha256sum "$1" | awk '{print $1}'; }

on_error() {
    local line=$1 status=$2
    trap - ERR
    set +e
    printf 'ERROR: FCC first-name update failed near line %s (status %s).\n' "$line" "$status" >&2
    if [[ $INSTALL_ACTIVE -eq 1 ]]; then
        dvsm_transaction_rollback >&2 || printf 'ERROR: automatic rollback failed; use the protected backup.\n' >&2
        systemctl daemon-reload >/dev/null 2>&1 || true
        if [[ -f "$TIMER_TARGET" && ! -L "$TIMER_TARGET" ]]; then systemctl enable --now "$TIMER_UNIT" >/dev/null 2>&1 || true; fi
    fi
    cleanup
    exit "$status"
}
trap 'on_error $LINENO $?' ERR
trap cleanup EXIT

hash_is_supported() {
    local actual=$1; shift
    local supported
    for supported in "$@"; do [[ "$actual" == "$supported" ]] && return 0; done
    return 1
}

require_owner_mode() {
    local path=$1 expected owner=$2 group=$3 mode=$4 actual
    actual=$(stat -c '%U:%G:%a' "$path")
    [[ "$actual" == "$owner:$group:$mode" ]] || die "Unsafe ownership or mode for $path: $actual (expected $owner:$group:$mode)"
}

verify_installed_modification() {
    require_file "$LH_TARGET"; require_file "$LOCALTX_TARGET"; require_file "$HELPER_TARGET"; require_file "$DATABASE_TARGET"
    require_owner_mode "$LH_TARGET" root root 644
    require_owner_mode "$LOCALTX_TARGET" root root 644
    require_owner_mode "$HELPER_TARGET" root root 644
    require_owner_mode "$DATABASE_TARGET" root www-data 644
    cp -- "$LH_TARGET" "$WORK_DIR/lh.php"
    cp -- "$LOCALTX_TARGET" "$WORK_DIR/localtx.php"
    python3 "$PATCHER" --lh "$WORK_DIR/lh.php" --localtx "$WORK_DIR/localtx.php"
    cmp -s "$LH_TARGET" "$WORK_DIR/lh.php" || die "Installed lh.php is not the current supported modification."
    cmp -s "$LOCALTX_TARGET" "$WORK_DIR/localtx.php" || die "Installed localtx.php is not the current supported modification."
    local actual
    actual=$(file_hash "$HELPER_TARGET"); [[ "$actual" == "$HELPER_SHA256" ]] || die "Unsupported installed FCC helper checksum: $actual"
    python3 "$BUILDER" --validate "$DATABASE_TARGET" >/dev/null
}

preflight() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this updater with sudo."
    . /etc/os-release
    [[ ${ID:-} == debian ]] || die "Unsupported OS: ${ID:-unknown}"
    case "${VERSION_ID:-}" in 12|13) ;; *) die "Unsupported Debian version: ${VERSION_ID:-unknown}" ;; esac
    for command in awk cmp cp curl date flock install mktemp mv python3 rm sha256sum stat systemctl; do require_command "$command"; done
    require_file "$BUILDER"; require_file "$PATCHER"; require_file "$TRANSACTION_LIBRARY"
    [[ "$(file_hash "$BUILDER")" == "$BUILDER_SHA256" ]] || die "Installed FCC builder checksum is unsupported."
    [[ "$(file_hash "$PATCHER")" == "$PATCHER_SHA256" ]] || die "Installed FCC dashboard patcher checksum is unsupported."
    [[ "$(file_hash "$TRANSACTION_LIBRARY")" == "$TRANSACTION_SHA256" ]] || die "Installed transaction helper checksum is unsupported."
    exec 9>"$LOCK_FILE"
    flock -n 9 || die "Another FCC first-name update is already running."
    [[ -d "$WORK_ROOT" && ! -L "$WORK_ROOT" ]] || die "Required work root is unavailable: $WORK_ROOT"
    WORK_DIR=$(mktemp -d "$WORK_ROOT/.dvswitch-fcc-firstnames.XXXXXX")
    verify_installed_modification
}

run_remove_updater() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this utility with sudo."
    for command in cp date install mktemp mv rm stat systemctl; do require_command "$command"; done
    require_file "$TRANSACTION_LIBRARY"
    local target
    for target in "$UPDATER_TARGET" "$BUILDER" "$PATCHER" "$TRANSACTION_LIBRARY" "$SERVICE_TARGET" "$TIMER_TARGET"; do require_file "$target"; done
    . "$TRANSACTION_LIBRARY"
    dvsm_transaction_begin "$BACKUP_ROOT"
    for target in "$UPDATER_TARGET" "$BUILDER" "$PATCHER" "$TRANSACTION_LIBRARY" "$SERVICE_TARGET" "$TIMER_TARGET"; do dvsm_backup_file "$target"; done
    INSTALL_ACTIVE=1
    systemctl disable --now "$TIMER_UNIT"
    rm -f -- "$SERVICE_TARGET" "$TIMER_TARGET" "$BUILDER" "$PATCHER" "$TRANSACTION_LIBRARY" "$UPDATER_TARGET"
    systemctl daemon-reload
    for target in "$UPDATER_TARGET" "$BUILDER" "$PATCHER" "$TRANSACTION_LIBRARY" "$SERVICE_TARGET" "$TIMER_TARGET"; do [[ ! -e "$target" && ! -L "$target" ]]; done
    INSTALL_ACTIVE=0
    printf 'PASS: FCC weekly updater removed; the installed Name modification and database were preserved.\nBackup: %s\n' "$DVSM_TRANSACTION_DIR"
}

run_update() {
    preflight
    local archive="$WORK_DIR/l_amat.zip" candidate="$WORK_DIR/fcc-first-names.dat"
    printf 'FCC archive: downloading weekly Amateur Radio Service file...\n'
    curl --fail --location --silent --show-error --connect-timeout 30 --max-time 900 --retry 2 --output "$archive" "$FCC_URL"
    [[ -s "$archive" && ! -L "$archive" ]] || die "FCC archive download is empty or invalid."
    printf 'FCC archive: downloaded %s bytes.\n' "$(stat -c %s "$archive")"
    python3 "$BUILDER" --archive "$archive" --output "$candidate" >/dev/null
    rm -f -- "$archive"
    local count size checksum
    count=$(python3 "$BUILDER" --validate "$candidate")
    size=$(stat -c %s "$candidate")
    checksum=$(file_hash "$candidate")
    printf 'FCC database: rebuilt and validated.\nRecords: %s\nBytes: %s\nSHA256: %s\n' "$count" "$size" "$checksum"
    if cmp -s "$candidate" "$DATABASE_TARGET"; then
        printf 'PASS: installed FCC first-name database is byte-for-byte identical. No backup or replacement was needed.\n'
        return
    fi
    . "$TRANSACTION_LIBRARY"
    dvsm_transaction_begin "$BACKUP_ROOT"
    dvsm_backup_file "$DATABASE_TARGET"
    INSTALL_ACTIVE=1
    dvsm_install_candidate "$candidate" "$DATABASE_TARGET"
    [[ "$(python3 "$BUILDER" --validate "$DATABASE_TARGET")" == "$count" ]]
    [[ "$(file_hash "$DATABASE_TARGET")" == "$checksum" ]]
    require_owner_mode "$DATABASE_TARGET" root www-data 644
    INSTALL_ACTIVE=0
    printf 'PASS: FCC first-name database installed atomically.\nBackup: %s\n' "$DVSM_TRANSACTION_DIR"
}

case "${1:-}" in
    "") run_update ;;
    --remove-updater) run_remove_updater ;;
    --version) printf 'DVSwitch FCC first-name updater %s\n' "$UPDATER_VERSION" ;;
    *) die "Unknown option: $1" ;;
esac
