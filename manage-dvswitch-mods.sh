#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Repository-wide front end. Existing repair/modification files remain the
# authoritative installers and validators; this manager selects and records
# them so its own installations can be reversed safely.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly STATE_DIR="/var/lib/dvswitch-mods/manager"
readonly STATE_FILE="$STATE_DIR/active-installs.tsv"
readonly LOCK_FILE="$STATE_DIR/manager.lock"

readonly -a COMPONENTS=(
    mmdvm-spacing
    dvswitch-txt-updater
    p25-audio-announcement
    p25-dashboard
    p25-nxdn-json
    p25-nxdn-friendly-names
    dstar-tx-ref
    dmr-friendly-names
    ysf-dashboard-null
    dashboard-fcc-first-names
    dashboard-targets
)

COMPONENT=""
CHILD_SCRIPT=""
BACKUP_ROOT=""
UNINSTALL_ACTION="--restore"

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
usage() {
    printf '%s\n' \
        "DVSwitch-Mods manager $SCRIPT_VERSION" \
        "Usage: sudo $(basename "$0") --list" \
        "       sudo $(basename "$0") --status" \
        "       sudo $(basename "$0") --check COMPONENT|all" \
        "       sudo $(basename "$0") --install COMPONENT|all" \
        "       sudo $(basename "$0") --uninstall COMPONENT|all" \
        "" \
        "Only installations performed and recorded by this manager can be" \
        "uninstalled through it. Uninstall operations run in strict reverse" \
        "installation order so overlapping DVSwitch files remain consistent."
}

require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this operation with sudo."; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
require_regular() { [[ -f "$1" && ! -L "$1" ]] || die "Required regular file is unavailable: $1"; }

select_component() {
    COMPONENT=$1
    UNINSTALL_ACTION="--restore"
    case "$COMPONENT" in
        mmdvm-spacing)
            CHILD_SCRIPT="$SCRIPT_DIR/manage-mmdvm-spacing.sh"
            UNINSTALL_ACTION="--uninstall"
            case "$(file -b /opt/MMDVM_Bridge/MMDVM_Bridge 2>/dev/null || true)" in
                *"ELF 64-bit"*"ARM aarch64"*) BACKUP_ROOT="/var/backups/dvswitch-mods/mmdvm-spacing" ;;
                *"ELF 32-bit"*"ARM"*"EABI5"*"hard-float"*) BACKUP_ROOT="/var/backups/dvswitch-mods/mmdvm-spacing-armhf" ;;
                *"ELF 64-bit"*"x86-64"*|*"ELF 32-bit"*"Intel 80386"*|*"ELF 32-bit"*"Intel i386"*) BACKUP_ROOT="/var/backups/dvswitch-mods/mmdvm-spacing-x86" ;;
                *) die "Cannot select an MMDVM repair for the installed binary." ;;
            esac
            ;;
        dvswitch-txt-updater) CHILD_SCRIPT="$SCRIPT_DIR/repair-dvswitch-txt-updater.sh"; BACKUP_ROOT="/var/backups/dvswitch-mods/txt-updater" ;;
        p25-audio-announcement) CHILD_SCRIPT="$SCRIPT_DIR/repair-p25-audio-announcement.sh"; BACKUP_ROOT="/var/backups/dvswitch-mods/p25-audio-announcement" ;;
        p25-dashboard) CHILD_SCRIPT="$SCRIPT_DIR/repair-p25-dashboard.sh"; BACKUP_ROOT="/var/backups/dvswitch-mods/p25-dashboard" ;;
        p25-nxdn-json) CHILD_SCRIPT="$SCRIPT_DIR/mod-p25-nxdn-json.sh"; BACKUP_ROOT="/var/backups/dvswitch-mods/p25-nxdn-json" ;;
        p25-nxdn-friendly-names) CHILD_SCRIPT="$SCRIPT_DIR/mod-p25-nxdn-friendly-names.sh"; BACKUP_ROOT="/var/backups/dvswitch-mods/p25-nxdn-friendly-names" ;;
        dstar-tx-ref) CHILD_SCRIPT="$SCRIPT_DIR/mod-dstar-tx-ref.sh"; BACKUP_ROOT="/var/backups/dvswitch-mods/dstar-tx-ref" ;;
        dmr-friendly-names) CHILD_SCRIPT="$SCRIPT_DIR/mod-dmr-friendly-names.sh"; BACKUP_ROOT="/var/backups/dvswitch-mods/dmr-friendly-names" ;;
        ysf-dashboard-null) CHILD_SCRIPT="$SCRIPT_DIR/repair-ysf-dashboard-null.sh"; BACKUP_ROOT="/var/backups/dvswitch-mods/ysf-dashboard-null" ;;
        dashboard-fcc-first-names) CHILD_SCRIPT="$SCRIPT_DIR/mod-dashboard-fcc-first-names.sh"; BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-fcc-first-names"; UNINSTALL_ACTION="--uninstall" ;;
        dashboard-targets) CHILD_SCRIPT="$SCRIPT_DIR/mod-dashboard-targets.sh"; BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-targets" ;;
        *) die "Unknown component: $COMPONENT" ;;
    esac
    require_regular "$CHILD_SCRIPT"
    [[ -x "$CHILD_SCRIPT" ]] || die "Component script is not executable: $CHILD_SCRIPT"
}

initialize_state() {
    require_root
    for command in cat chmod chown comm file find flock install mktemp mv sed sort tail uname wc; do require_command "$command"; done
    [[ ! -L "$STATE_DIR" ]] || die "Refusing symbolic-link state directory: $STATE_DIR"
    install -d -o root -g root -m 0700 "$STATE_DIR"
    if [[ ! -e "$STATE_FILE" ]]; then
        install -o root -g root -m 0600 /dev/null "$STATE_FILE"
    fi
    require_regular "$STATE_FILE"
    chown root:root "$STATE_FILE"
    chmod 0600 "$STATE_FILE"
    [[ ! -L "$LOCK_FILE" ]] || die "Refusing symbolic-link lock file: $LOCK_FILE"
    exec 9>"$LOCK_FILE"
    chown root:root "$LOCK_FILE"
    chmod 0600 "$LOCK_FILE"
    flock -n 9 || die "Another DVSwitch-Mods manager operation is running."
}

list_components() {
    printf 'Available components (installation order):\n'
    printf '  %s\n' "${COMPONENTS[@]}"
}

show_status() {
    require_root
    if [[ ! -e "$STATE_FILE" ]]; then
        printf 'No active installations are recorded by this manager.\n'
        return
    fi
    require_regular "$STATE_FILE"
    if [[ ! -s "$STATE_FILE" ]]; then
        printf 'No active installations are recorded by this manager.\n'
        return
    fi
    printf 'Active manager-recorded installations (oldest first):\n'
    while IFS=$'\t' read -r component script root backup action; do
        [[ -n "$component" ]] || continue
        printf '  %s -> %s/%s (%s)\n' "$component" "$root" "$backup" "$action"
    done < "$STATE_FILE"
}

is_arm64_host() { [[ $(uname -m) == aarch64 ]]; }

should_skip_all_component() {
    [[ $1 == p25-audio-announcement ]] && ! is_arm64_host
}

snapshot_backups() {
    local root=$1
    if [[ -d "$root" ]]; then
        find "$root" -mindepth 1 -maxdepth 1 -type d -name 'install-*' -printf '%f\n' | sort
    fi
}

record_install() {
    local component=$1 script=$2 root=$3 backup=$4 action=$5 temporary
    [[ "$component" != *$'\t'* && "$script" != *$'\t'* && "$root" != *$'\t'* && "$backup" != *$'\t'* ]] || die "Invalid state value."
    temporary=$(mktemp --tmpdir="$STATE_DIR" .active-installs.XXXXXX)
    cat "$STATE_FILE" > "$temporary"
    printf '%s\t%s\t%s\t%s\t%s\n' "$component" "$script" "$root" "$backup" "$action" >> "$temporary"
    chown root:root "$temporary"
    chmod 0600 "$temporary"
    mv -fT -- "$temporary" "$STATE_FILE"
}

install_one() {
    local requested=$1 before after additions backup count
    select_component "$requested"
    printf '\n=== CHECK: %s ===\n' "$COMPONENT"
    "$CHILD_SCRIPT" --check
    before=$(snapshot_backups "$BACKUP_ROOT")
    printf '\n=== INSTALL: %s ===\n' "$COMPONENT"
    "$CHILD_SCRIPT" --install
    after=$(snapshot_backups "$BACKUP_ROOT")
    additions=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed '/^$/d')
    count=$(printf '%s\n' "$additions" | sed '/^$/d' | wc -l)
    if [[ $count -eq 0 ]]; then
        printf 'NOTICE: %s was already installed; no new backup was created or recorded.\n' "$COMPONENT"
        return
    fi
    [[ $count -eq 1 ]] || die "$COMPONENT created an unexpected number of backups; inspect $BACKUP_ROOT manually."
    backup=$additions
    [[ -d "$BACKUP_ROOT/$backup" && ! -L "$BACKUP_ROOT/$backup" ]] || die "New protected backup is unavailable: $BACKUP_ROOT/$backup"
    record_install "$COMPONENT" "$(basename "$CHILD_SCRIPT")" "$BACKUP_ROOT" "$backup" "$UNINSTALL_ACTION"
    printf 'PASS: recorded reversible installation of %s using %s.\n' "$COMPONENT" "$backup"
    printf '\n=== POST-INSTALL CHECK: %s ===\n' "$COMPONENT"
    "$CHILD_SCRIPT" --check
}

check_one() {
    select_component "$1"
    printf '\n=== CHECK: %s ===\n' "$COMPONENT"
    "$CHILD_SCRIPT" --check
}

last_state_line() { tail -n 1 "$STATE_FILE"; }

remove_last_state_line() {
    local temporary
    temporary=$(mktemp --tmpdir="$STATE_DIR" .active-installs.XXXXXX)
    sed '$d' "$STATE_FILE" > "$temporary"
    chown root:root "$temporary"
    chmod 0600 "$temporary"
    mv -fT -- "$temporary" "$STATE_FILE"
}

uninstall_one() {
    local requested=$1 line component script root backup action expected_script expected_root expected_action
    [[ -s "$STATE_FILE" ]] || die "No manager-recorded installation is available to uninstall."
    line=$(last_state_line)
    IFS=$'\t' read -r component script root backup action <<< "$line"
    [[ "$requested" == "$component" ]] || die "Unsafe uninstall order: $component was installed later and must be uninstalled first."
    select_component "$component"
    expected_script=$(basename "$CHILD_SCRIPT")
    expected_root=$BACKUP_ROOT
    expected_action=$UNINSTALL_ACTION
    [[ "$script" == "$expected_script" && "$root" == "$expected_root" && "$action" == "$expected_action" ]] || die "Recorded state does not match the component registry; refusing uninstall."
    [[ -d "$root/$backup" && ! -L "$root/$backup" ]] || die "Recorded backup is unavailable: $root/$backup"
    require_regular "$SCRIPT_DIR/$script"
    printf '\n=== UNINSTALL: %s ===\n' "$component"
    "$SCRIPT_DIR/$script" "$action" "$backup"
    remove_last_state_line
    printf 'PASS: uninstalled %s using its recorded protected backup.\n' "$component"
}

check_requested() {
    local requested=$1 component
    if [[ $requested == all ]]; then
        for component in "${COMPONENTS[@]}"; do
            if should_skip_all_component "$component"; then
                printf '\n=== SKIP: %s requires an ARM64 host ===\n' "$component"
                continue
            fi
            check_one "$component"
        done
    else
        check_one "$requested"
    fi
}

install_requested() {
    local requested=$1 component
    if [[ $requested == all ]]; then
        for component in "${COMPONENTS[@]}"; do
            if should_skip_all_component "$component"; then
                printf '\n=== SKIP: %s requires an ARM64 host ===\n' "$component"
                continue
            fi
            install_one "$component"
        done
    else
        install_one "$requested"
    fi
}

uninstall_requested() {
    local requested=$1 line component
    if [[ $requested == all ]]; then
        while [[ -s "$STATE_FILE" ]]; do
            line=$(last_state_line)
            IFS=$'\t' read -r component _ <<< "$line"
            uninstall_one "$component"
        done
        printf 'PASS: all manager-recorded installations were uninstalled in reverse order.\n'
    else
        uninstall_one "$requested"
    fi
}

main() {
    case "${1:-}" in
        --list) [[ $# -eq 1 ]] || die "Unexpected arguments."; list_components ;;
        --status) [[ $# -eq 1 ]] || die "Unexpected arguments."; show_status ;;
        --check) [[ $# -eq 2 ]] || die "--check requires a component name or all."; require_root; check_requested "$2" ;;
        --install) [[ $# -eq 2 ]] || die "--install requires a component name or all."; initialize_state; install_requested "$2" ;;
        --uninstall) [[ $# -eq 2 ]] || die "--uninstall requires a component name or all."; initialize_state; uninstall_requested "$2" ;;
        --help|-h) usage ;;
        "") usage; exit 2 ;;
        *) die "Unknown option: $1" ;;
    esac
}

main "$@"
