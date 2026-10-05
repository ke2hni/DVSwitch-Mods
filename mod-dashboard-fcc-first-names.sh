#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="1.4.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PATCHER="$SCRIPT_DIR/lib/patch_dashboard_first_names.py"
readonly BUILDER="$SCRIPT_DIR/lib/build_fcc_first_names.py"
readonly HELPER_SOURCE="$SCRIPT_DIR/lib/dvswitch_mods_fcc_first_names.php"
readonly TRANSACTION_LIBRARY="$SCRIPT_DIR/lib/transaction.sh"
readonly UPDATER_SOURCE="$SCRIPT_DIR/lib/dvswitch_fcc_first_names_update.sh"
readonly SERVICE_SOURCE="$SCRIPT_DIR/systemd/dvswitch-fcc-first-names-update.service"
readonly TIMER_SOURCE="$SCRIPT_DIR/systemd/dvswitch-fcc-first-names-update.timer"
readonly LH_TARGET="/usr/share/dvswitch/include/lh.php"
readonly HELPER_TARGET="/usr/share/dvswitch/include/dvswitch_mods_fcc_first_names.php"
readonly CALLSIGN_DESCRIPTIONS_SOURCE="$SCRIPT_DIR/data/callsign-descriptions.tsv"
readonly CALLSIGN_DESCRIPTIONS_TARGET="/etc/dvswitch-mods/callsign-descriptions.tsv"
readonly DATABASE_TARGET="/var/lib/mmdvm/dvswitch-mods-fcc-first-names.dat"
readonly CTY_DATABASE_TARGET="/var/lib/mmdvm/dvswitch-mods-cty.dat"
readonly UPDATER_TARGET="/usr/local/sbin/dvswitch-fcc-first-names-update"
readonly INSTALLED_LIBRARY_DIR="/usr/local/lib/dvswitch-mods"
readonly BUILDER_TARGET="$INSTALLED_LIBRARY_DIR/build_fcc_first_names.py"
readonly PATCHER_TARGET="$INSTALLED_LIBRARY_DIR/patch_dashboard_first_names.py"
readonly TRANSACTION_TARGET="$INSTALLED_LIBRARY_DIR/transaction.sh"
readonly SERVICE_TARGET="/etc/systemd/system/dvswitch-fcc-first-names-update.service"
readonly TIMER_TARGET="/etc/systemd/system/dvswitch-fcc-first-names-update.timer"
readonly TIMER_UNIT="dvswitch-fcc-first-names-update.timer"
readonly WORK_ROOT="/var/lib/mmdvm"
readonly FCC_URL="https://data.fcc.gov/download/pub/uls/complete/l_amat.zip"
readonly CTY_URL="https://www.country-files.com/cty/cty.dat"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-fcc-first-names"
readonly DASHBOARD_URL="https://127.0.0.1/dvswitch/"

WORK_DIR=""
INSTALL_ACTIVE=0
TIMER_CHANGED=0
SYSTEMD_CHANGED=0

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
        if [[ $SYSTEMD_CHANGED -eq 1 ]]; then systemctl daemon-reload >/dev/null 2>&1 || true; fi
        if [[ -f "$TIMER_TARGET" && ! -L "$TIMER_TARGET" ]]; then
            if [[ $SYSTEMD_CHANGED -eq 1 ]]; then
                systemctl enable "$TIMER_UNIT" >/dev/null 2>&1 || true
                systemctl restart "$TIMER_UNIT" >/dev/null 2>&1 || true
            elif ! systemctl is-enabled --quiet "$TIMER_UNIT" || ! systemctl is-active --quiet "$TIMER_UNIT"; then
                systemctl enable --now "$TIMER_UNIT" >/dev/null 2>&1 || true
            fi
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
    require_file "$PATCHER"; require_file "$BUILDER"; require_file "$HELPER_SOURCE"; require_file "$CALLSIGN_DESCRIPTIONS_SOURCE"; require_file "$TRANSACTION_LIBRARY"
    require_file "$UPDATER_SOURCE"; require_file "$SERVICE_SOURCE"; require_file "$TIMER_SOURCE"
    require_file "$LH_TARGET"
    if [[ -e "$CALLSIGN_DESCRIPTIONS_TARGET" || -L "$CALLSIGN_DESCRIPTIONS_TARGET" ]]; then require_file "$CALLSIGN_DESCRIPTIONS_TARGET"; fi
    php -l "$LH_TARGET" >/dev/null; php -l "$HELPER_SOURCE" >/dev/null
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

patcher_structure_supported() {
    local target=$1
    grep -Fq 'FCC first-name activity columns' "$target" &&
    grep -Fq 'dvsModsFccFirstName($listElem[2])' "$target" &&
    grep -Fq 'dvsModsDmrIdCallsign($listElem[2])' "$target" &&
    grep -Fq '<th>Name</th>' "$target"
}

# systemd accepts trailing blank lines; ignore only those when validating a
# deployed unit so harmless editor-added whitespace does not block --check.
unit_file_matches() {
    python3 - "$1" "$2" <<'PY'
from pathlib import Path
import sys

def normalized(path):
    lines = Path(path).read_bytes().splitlines()
    while lines and not lines[-1].strip():
        lines.pop()
    return b"\n".join(lines) + (b"\n" if lines else b"")

raise SystemExit(0 if normalized(sys.argv[1]) == normalized(sys.argv[2]) else 1)
PY
}

# The previous FCC timer release randomized the weekly run by up to 96 hours.
# Accept that exact prior setting so --check can report it as upgradeable.
timer_file_matches_supported() {
    unit_file_matches "$1" "$2" && return 0
    python3 - "$1" "$2" <<'PY'
from pathlib import Path
import sys

def normalized(data):
    lines = data.splitlines()
    while lines and not lines[-1].strip():
        lines.pop()
    return b"\n".join(lines) + (b"\n" if lines else b"")

expected = Path(sys.argv[1]).read_bytes()
old = b"RandomizedDelaySec=96h"
current = b"RandomizedDelaySec=6h"
if expected.count(current) != 1:
    raise SystemExit(1)
previous = expected.replace(current, old, 1)
installed = Path(sys.argv[2]).read_bytes()
raise SystemExit(0 if normalized(installed) == normalized(previous) else 1)
PY
}

updater_release_state() {
    local state
    state=$(updater_state)
    [[ "$state" != absent ]] || { printf 'absent'; return; }
    if [[ "$state" == legacy ]]; then
        [[ "$(stat -c '%U:%G:%a' "$UPDATER_TARGET")" == root:root:755 ]] || die "Incorrect legacy updater ownership or mode."
        for target in "$BUILDER_TARGET" "$TRANSACTION_TARGET" "$SERVICE_TARGET" "$TIMER_TARGET"; do
            [[ "$(stat -c '%U:%G:%a' "$target")" == root:root:644 ]] || die "Incorrect ownership or mode: $target"
        done
        systemctl is-enabled --quiet "$TIMER_UNIT" || die "FCC weekly update timer is not enabled."
        systemctl is-active --quiet "$TIMER_UNIT" || die "FCC weekly update timer is not active."
        printf 'upgradeable'
        return
    fi
    if patcher_structure_supported "$PATCHER_TARGET"; then
        cmp -s "$BUILDER" "$BUILDER_TARGET" || die "Installed FCC builder does not match the supported previous release."
        cmp -s "$TRANSACTION_LIBRARY" "$TRANSACTION_TARGET" || die "Installed FCC transaction helper does not match the supported previous release."
        unit_file_matches "$SERVICE_SOURCE" "$SERVICE_TARGET" || die "Installed FCC systemd service does not match the supported previous release."
        timer_file_matches_supported "$TIMER_SOURCE" "$TIMER_TARGET" || die "Installed FCC timer does not match the supported previous release."
        [[ "$(stat -c '%U:%G:%a' "$UPDATER_TARGET")" == root:root:755 ]] || die "Incorrect updater ownership or mode."
        for target in "$BUILDER_TARGET" "$PATCHER_TARGET" "$TRANSACTION_TARGET" "$SERVICE_TARGET" "$TIMER_TARGET"; do
            [[ "$(stat -c '%U:%G:%a' "$target")" == root:root:644 ]] || die "Incorrect ownership or mode: $target"
        done
        systemctl is-enabled --quiet "$TIMER_UNIT" || die "FCC weekly update timer is not enabled."
        systemctl is-active --quiet "$TIMER_UNIT" || die "FCC weekly update timer is not active."
        if cmp -s "$UPDATER_SOURCE" "$UPDATER_TARGET" &&
           cmp -s "$PATCHER" "$PATCHER_TARGET" &&
           cmp -s "$BUILDER" "$BUILDER_TARGET" &&
           cmp -s "$TRANSACTION_LIBRARY" "$TRANSACTION_TARGET" &&
           unit_file_matches "$SERVICE_SOURCE" "$SERVICE_TARGET" &&
           unit_file_matches "$TIMER_SOURCE" "$TIMER_TARGET"; then
            printf 'current'
        else
            printf 'upgradeable'
        fi
        return
    fi
    cmp -s "$UPDATER_SOURCE" "$UPDATER_TARGET" || die "Installed FCC updater does not match this release."
    cmp -s "$PATCHER" "$PATCHER_TARGET" || die "Installed FCC dashboard patcher does not match this release."
    cmp -s "$BUILDER" "$BUILDER_TARGET" || die "Installed FCC builder does not match this release."
    cmp -s "$TRANSACTION_LIBRARY" "$TRANSACTION_TARGET" || die "Installed FCC transaction helper does not match this release."
    unit_file_matches "$SERVICE_SOURCE" "$SERVICE_TARGET" || die "Installed FCC systemd service does not match this release."
    [[ "$(stat -c '%U:%G:%a' "$UPDATER_TARGET")" == root:root:755 ]] || die "Incorrect updater ownership or mode."
    for target in "$BUILDER_TARGET" "$PATCHER_TARGET" "$TRANSACTION_TARGET" "$SERVICE_TARGET" "$TIMER_TARGET"; do
        [[ "$(stat -c '%U:%G:%a' "$target")" == root:root:644 ]] || die "Incorrect ownership or mode: $target"
    done
    systemctl is-enabled --quiet "$TIMER_UNIT" || die "FCC weekly update timer is not enabled."
    systemctl is-active --quiet "$TIMER_UNIT" || die "FCC weekly update timer is not active."
    if cmp -s "$UPDATER_SOURCE" "$UPDATER_TARGET" && cmp -s "$PATCHER" "$PATCHER_TARGET" && cmp -s "$BUILDER" "$BUILDER_TARGET" && cmp -s "$TRANSACTION_LIBRARY" "$TRANSACTION_TARGET" && unit_file_matches "$SERVICE_SOURCE" "$SERVICE_TARGET" && unit_file_matches "$TIMER_SOURCE" "$TIMER_TARGET"; then
        printf 'current'
    else
        printf 'upgradeable'
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
    if [[ "$target" == "$SERVICE_TARGET" || "$target" == "$TIMER_TARGET" ]]; then SYSTEMD_CHANGED=1; fi
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
    python3 "$PATCHER" --lh "$WORK_DIR/lh.php"
    php -l "$WORK_DIR/lh.php" >/dev/null
    local lh_hash
    lh_hash=$(file_hash "$WORK_DIR/lh.php")
    python3 "$PATCHER" --lh "$WORK_DIR/lh.php"
    [[ "$lh_hash" == "$(file_hash "$WORK_DIR/lh.php")" ]] || die "Dashboard patch is not idempotent."
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

validate_cty() {
    local file=$1 bytes
    [[ -f "$file" && ! -L "$file" ]] || return 1
    bytes=$(stat -c %s "$file") || return 1
    (( bytes >= 10000 && bytes <= 2000000 )) || return 1
    grep -q 'AD1C' "$file" && grep -q '^Argentina:' "$file"
}

prepare_cty_candidate() {
    local archive="$WORK_DIR/cty.dat.download" candidate="$WORK_DIR/cty.dat"
    if validate_cty "$CTY_DATABASE_TARGET"; then
        printf 'CTY.DAT: valid country database already installed.\n'
        return 0
    fi
    if [[ -e "$CTY_DATABASE_TARGET" || -L "$CTY_DATABASE_TARGET" ]] && [[ ! -f "$CTY_DATABASE_TARGET" || -L "$CTY_DATABASE_TARGET" ]]; then
        die "Refusing unsupported CTY.DAT target state: $CTY_DATABASE_TARGET"
    fi
    printf 'CTY.DAT: downloading country/entity database for initial installation...\n'
    if curl --fail --location --silent --show-error --connect-timeout 30 --max-time 120 --retry 2 --output "$archive" "$CTY_URL" && validate_cty "$archive"; then
        cp -- "$archive" "$candidate"
        printf 'CTY.DAT: downloaded and validated (%s bytes).\n' "$(stat -c %s "$candidate")"
        return 0
    fi
    rm -f -- "$archive" "$candidate"
    die "CTY.DAT download or validation failed. No installation changes have been made; correct the connection/feed issue and rerun --install."
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
    if cmp -s "$LH_TARGET" "$WORK_DIR/lh.php"; then
        printf 'ALREADY MODIFIED: Gateway Activity worldwide DMR/FCC Name column is installed; Local Activity was not modified.\n'
    else
        printf 'MODIFICATION READY:\nBefore lh.php:      %s\nAfter lh.php:       %s\nLocal Activity:    unchanged\n' "$(file_hash "$LH_TARGET")" "$(file_hash "$WORK_DIR/lh.php")"
    fi
    if [[ -f "$DATABASE_TARGET" && ! -L "$DATABASE_TARGET" ]]; then
        local database_count database_checksum
        database_count=$(python3 "$BUILDER" --validate "$DATABASE_TARGET")
        database_checksum=$(file_hash "$DATABASE_TARGET")
        printf 'FCC database: %s validated records, %s bytes.\nFCC database SHA256: %s\n' "$database_count" "$(stat -c %s "$DATABASE_TARGET")" "$database_checksum"
    else printf 'FCC database: not installed; --install will download and build it.\n'; fi
    if validate_cty "$CTY_DATABASE_TARGET"; then
        printf 'CTY.DAT: installed and validated (%s bytes).\n' "$(stat -c %s "$CTY_DATABASE_TARGET")"
    else
        printf 'CTY.DAT: missing or invalid; --install will attempt a bounded country-file download.\n'
    fi
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
    if [[ -f "$CALLSIGN_DESCRIPTIONS_TARGET" ]]; then printf 'Custom callsign descriptions: editable file present at %s.\n' "$CALLSIGN_DESCRIPTIONS_TARGET"; else printf 'MODIFICATION READY: --install will create the editable custom callsign file at %s.\n' "$CALLSIGN_DESCRIPTIONS_TARGET"; fi
    printf 'PASS: supported activity-table structure. No files changed.\n'
}

run_install() {
    preflight; prepare_dashboard
    local cty_ready=0
    if validate_cty "$CTY_DATABASE_TARGET"; then cty_ready=1; fi
    if cmp -s "$LH_TARGET" "$WORK_DIR/lh.php" && [[ -f "$HELPER_TARGET" ]] && cmp -s "$HELPER_SOURCE" "$HELPER_TARGET" && [[ -f "$DATABASE_TARGET" ]] && [[ -f "$CALLSIGN_DESCRIPTIONS_TARGET" ]] && python3 "$BUILDER" --validate "$DATABASE_TARGET" >/dev/null && [[ "$(updater_release_state)" == current ]] && [[ $cty_ready -eq 1 ]]; then
        printf 'PASS: worldwide DMR/FCC dashboard Name modification is already installed. No files changed.\n'; return
    fi
    if [[ $cty_ready -eq 0 ]]; then prepare_cty_candidate; fi
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
    stage_install_component "$HELPER_SOURCE" "$HELPER_TARGET" root root 0644
    if [[ ! -e "$CALLSIGN_DESCRIPTIONS_TARGET" ]]; then
        backup_target "$CALLSIGN_DESCRIPTIONS_TARGET"
        install -d -o root -g root -m 0755 "$(dirname "$CALLSIGN_DESCRIPTIONS_TARGET")"
        dvsm_install_new_candidate "$CALLSIGN_DESCRIPTIONS_SOURCE" "$CALLSIGN_DESCRIPTIONS_TARGET" root root 0644
    fi
    if [[ $database_ready -eq 0 ]]; then stage_install_component "$WORK_DIR/fcc-first-names.dat" "$DATABASE_TARGET" root www-data 0644; fi
    if [[ -f "$WORK_DIR/cty.dat" && ! -L "$WORK_DIR/cty.dat" ]]; then
        stage_install_component "$WORK_DIR/cty.dat" "$CTY_DATABASE_TARGET" root www-data 0644
    elif ! validate_cty "$CTY_DATABASE_TARGET"; then
        die "No validated CTY.DAT is available to complete the installation."
    fi
    php -l "$LH_TARGET" >/dev/null; php -l "$HELPER_TARGET" >/dev/null
    python3 "$BUILDER" --validate "$DATABASE_TARGET" >/dev/null
    validate_cty "$CTY_DATABASE_TARGET" || die "Installed CTY.DAT failed validation."
    if [[ $SYSTEMD_CHANGED -eq 1 ]]; then systemctl daemon-reload; fi
    if [[ $TIMER_CHANGED -eq 1 ]]; then
        systemctl enable "$TIMER_UNIT"
        systemctl restart "$TIMER_UNIT"
    elif ! systemctl is-enabled --quiet "$TIMER_UNIT" || ! systemctl is-active --quiet "$TIMER_UNIT"; then
        systemctl enable --now "$TIMER_UNIT"
    fi
    verify_updater_components
    systemctl reload apache2.service; dashboard_health
    INSTALL_ACTIVE=0
    printf 'PASS: worldwide DMR/FCC dashboard Name modification installed atomically.\nBackup: %s\n' "$DVSM_TRANSACTION_DIR"
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
    local name=$1 directory="$BACKUP_ROOT/$1" original_lh target custom_temporary=""
    [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name."
    [[ -d "$directory" && ! -L "$directory" ]] || die "Backup not found: $name"
    require_file "$directory/MANIFEST"
    original_lh=$(uninstall_backup_file "$directory" "$LH_TARGET")
    [[ -n "$WORK_DIR" ]] || WORK_DIR=$(mktemp -d "$WORK_ROOT/.dvswitch-fcc-firstnames.XXXXXX")
    install -d -m 0700 "$WORK_DIR/original"
    cp -- "$original_lh" "$WORK_DIR/original/lh.php"
    python3 "$PATCHER" --lh "$WORK_DIR/original/lh.php"
    if [[ -f "$CALLSIGN_DESCRIPTIONS_TARGET" && ! -L "$CALLSIGN_DESCRIPTIONS_TARGET" ]]; then
        custom_temporary="$WORK_DIR/callsign-descriptions.tsv"
        cp -a -- "$CALLSIGN_DESCRIPTIONS_TARGET" "$custom_temporary"
    fi
    . "$TRANSACTION_LIBRARY"
    dvsm_transaction_begin "$BACKUP_ROOT"
    for target in "$LH_TARGET" "$HELPER_TARGET" "$DATABASE_TARGET" "$CTY_DATABASE_TARGET" "$CALLSIGN_DESCRIPTIONS_TARGET"; do backup_target "$target"; done
    while IFS= read -r target; do backup_target "$target"; done < <(updater_targets)
    INSTALL_ACTIVE=1
    systemctl disable --now "$TIMER_UNIT" >/dev/null 2>&1 || true
    dvsm_restore_backup_set "$directory"
    if [[ -n "$custom_temporary" ]]; then
        install -d -o root -g root -m 0755 "$(dirname "$CALLSIGN_DESCRIPTIONS_TARGET")"
        local custom_restore
        custom_restore=$(mktemp --tmpdir="$(dirname "$CALLSIGN_DESCRIPTIONS_TARGET")" .dvswitch-custom-callsigns.XXXXXX)
        cp -a -- "$custom_temporary" "$custom_restore"
        mv -fT -- "$custom_restore" "$CALLSIGN_DESCRIPTIONS_TARGET"
    fi
    rm -f -- "$HELPER_TARGET" "$DATABASE_TARGET" "$CTY_DATABASE_TARGET"
    while IFS= read -r target; do rm -f -- "$target"; done < <(updater_targets)
    php -l "$LH_TARGET" >/dev/null
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
    if [[ -f "$UPDATER_TARGET" && ! -L "$UPDATER_TARGET" ]] && ! awk -F '\t' -v wanted="$PATCHER_TARGET" '$2 == wanted { found=1 } END { exit(found ? 0 : 1) }' "$directory/MANIFEST"; then
        rm -f -- "$PATCHER_TARGET"
    fi
    php -l "$LH_TARGET" >/dev/null
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
