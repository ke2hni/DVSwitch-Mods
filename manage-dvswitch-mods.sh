#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Repository-wide front end. Existing repair/modification files remain the
# authoritative installers and validators; this manager selects and records
# them so its own installations can be reversed safely.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="1.1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly STATE_DIR="/var/lib/dvswitch-mods/manager"
readonly STATE_FILE="$STATE_DIR/active-installs.tsv"
readonly LOCK_FILE="$STATE_DIR/manager.lock"
readonly DVSWITCH_COMMAND="/opt/MMDVM_Bridge/dvswitch.sh"
readonly DATABASE_UPDATE_STAMP="$STATE_DIR/last-database-update"
readonly DATABASE_MIN_INTERVAL=3600
readonly -a REQUIRED_DATABASES=(
    /var/lib/mmdvm/NXDNHosts.txt
    /var/lib/mmdvm/NXDNHosts.json
    /var/lib/mmdvm/P25Hosts.txt
    /var/lib/mmdvm/P25Hosts.json
    /var/lib/mmdvm/TGList_BM.txt
    /var/lib/mmdvm/YSFHosts.txt
    /var/lib/mmdvm/TGList_TGIF.txt
)
readonly -a RATE_LIMIT_EVIDENCE=(
    /var/lib/mmdvm/NXDNHosts.json
    /var/lib/mmdvm/P25Hosts.json
)

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
        "       sudo $(basename "$0") --reset-after-reinstall" \
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
                *) printf 'ERROR: Cannot select an MMDVM repair for the installed binary.\n' >&2; return 1 ;;
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
    for command in awk cat chmod chown comm file find flock install mktemp mv sed sort tail uname wc; do require_command "$command"; done
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

preflight_recorded_backups() {
    local component script root backup action missing=0
    [[ -s "$STATE_FILE" ]] || return 0
    while IFS=$'\t' read -r component script root backup action; do
        [[ -n "$component" ]] || continue
        if [[ -z "$script" || -z "$root" || -z "$backup" || -z "$action" ]]; then
            printf 'ERROR: Invalid manager record for %s.\n' "$component" >&2
            missing=1
        elif [[ ! -d "$root/$backup" || -L "$root/$backup" ]]; then
            printf 'ERROR: Recorded backup is missing for %s: %s/%s\n' "$component" "$root" "$backup" >&2
            missing=1
        fi
    done < "$STATE_FILE"
    if ((missing)); then
        printf '%s\n' \
            'ERROR: Installation stopped before changing any files.' \
            'The manager records do not match the available backups. This commonly happens after DVSwitch is uninstalled and reinstalled.' \
            "If DVSwitch was intentionally reinstalled, run: sudo ./$(basename "$0") --reset-after-reinstall" \
            'Then run the requested install command again. The reset archives the old records and does not delete any backups.' >&2
        return 1
    fi
}

reset_after_reinstall() {
    local stamp archive temporary
    [[ -s "$STATE_FILE" ]] || die "No active manager records exist; there is nothing to reset."
    if preflight_recorded_backups >/dev/null 2>&1; then
        die "Every recorded backup is available. Refusing to reset valid uninstall records."
    fi
    stamp=$(date +%Y%m%d-%H%M%S)
    archive="$STATE_DIR/active-installs.pre-reinstall-$stamp.tsv"
    [[ ! -e "$archive" ]] || die "State archive already exists: $archive"
    install -o root -g root -m 0600 "$STATE_FILE" "$archive"
    temporary=$(mktemp --tmpdir="$STATE_DIR" .active-installs.XXXXXX)
    chown root:root "$temporary"
    chmod 0600 "$temporary"
    mv -fT -- "$temporary" "$STATE_FILE"
    printf '%s\n' \
        "PASS: stale manager records were archived at $archive" \
        'No component backups or live DVSwitch files were deleted or changed.' \
        'Run the requested install command again.'
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

component_is_recorded() {
    local requested=$1 root backup
    local -a matches=()
    mapfile -t matches < <(awk -F '\t' -v wanted="$requested" '$1 == wanted { print $3 "\t" $4 }' "$STATE_FILE")
    [[ ${#matches[@]} -gt 0 ]] || return 1
    [[ ${#matches[@]} -eq 1 ]] || die "Manager state contains duplicate records for $requested."
    IFS=$'\t' read -r root backup <<< "${matches[0]}"
    [[ -d "$root/$backup" && ! -L "$root/$backup" ]] || die "Recorded backup is unavailable for $requested: $root/$backup"
    return 0
}

databases_ready() {
    local database
    for database in "${REQUIRED_DATABASES[@]}"; do
        [[ -f "$database" && ! -L "$database" && -s "$database" ]] || return 1
    done
}

ensure_databases() {
    local database modified newest=0 now age remaining temporary
    if databases_ready; then
        printf '\n=== DATABASE UPDATE ===\nAll required P25, NXDN, DMR, and YSF data files are already present; no download was requested.\n'
        return
    fi
    for database in "${RATE_LIMIT_EVIDENCE[@]}" "$DATABASE_UPDATE_STAMP"; do
        if [[ -f "$database" && ! -L "$database" ]]; then
            modified=$(stat -c '%Y' "$database")
            if ((modified > newest)); then newest=$modified; fi
        fi
    done
    now=$(date +%s)
    age=$((now - newest))
    if ((newest > 0 && age < DATABASE_MIN_INTERVAL)); then
        remaining=$((DATABASE_MIN_INTERVAL - age))
        die "Required data is missing, but a database update ran less than one hour ago. Wait $(((remaining + 59) / 60)) minute(s) before trying again."
    fi
    require_regular "$DVSWITCH_COMMAND"
    [[ -x "$DVSWITCH_COMMAND" ]] || die "DVSwitch updater is not executable: $DVSWITCH_COMMAND"
    printf '\n=== DATABASE UPDATE ===\nRequired dashboard data is missing. Running the installed validated DVSwitch updater.\n'
    temporary=$(mktemp --tmpdir="$STATE_DIR" .last-database-update.XXXXXX)
    printf '%s\n' "$now" > "$temporary"
    chown root:root "$temporary"
    chmod 0600 "$temporary"
    mv -fT -- "$temporary" "$DATABASE_UPDATE_STAMP"
    "$DVSWITCH_COMMAND" update
    for database in "${REQUIRED_DATABASES[@]}"; do
        [[ -f "$database" && ! -L "$database" && -s "$database" ]] || die "Database update did not produce a valid regular nonempty file: $database"
    done
    printf 'PASS: all required P25, NXDN, DMR, and YSF data files are present.\n'
}

check_one() {
    select_component "$1"
    printf '\n=== CHECK: %s ===\n' "$COMPONENT"
    "$CHILD_SCRIPT" --check
}

dependency_hint() {
    case "$1" in
        p25-nxdn-json) printf 'install dvswitch-txt-updater first' ;;
        p25-nxdn-friendly-names) printf 'install p25-dashboard and p25-nxdn-json first' ;;
        dstar-tx-ref) printf 'install p25-nxdn-friendly-names first' ;;
        dmr-friendly-names) printf 'install dstar-tx-ref first' ;;
        ysf-dashboard-null) printf 'install dmr-friendly-names first' ;;
        dashboard-targets) printf 'install dashboard-fcc-first-names first' ;;
        *) printf 'review the detailed error shown above' ;;
    esac
}

print_named_list() {
    local heading=$1
    shift
    printf '%s\n' "$heading"
    if [[ $# -eq 0 ]]; then
        printf '  - None\n'
    else
        printf '  - %s\n' "$@"
    fi
}

check_all() {
    local component output status index=0
    local -a installed=() ready=() failed=() skipped=() expected=()
    require_command grep
    for component in "${COMPONENTS[@]}"; do
        if should_skip_all_component "$component"; then
            printf '\n=== SKIP: %s ===\nRequires an ARM64 host; this component does not apply here.\n' "$component"
            skipped+=("$component — ARM64 hosts only")
            continue
        fi
        expected+=("$component")
        if ! select_component "$component"; then
            failed+=("$component — installed MMDVM_Bridge architecture or build could not be selected")
            continue
        fi
        printf '\n=== CHECK: %s ===\n' "$COMPONENT"
        set +e
        output=$("$CHILD_SCRIPT" --check 2>&1)
        status=$?
        set -e
        printf '%s\n' "$output"
        if [[ $status -ne 0 ]]; then
            failed+=("$COMPONENT — $(dependency_hint "$COMPONENT")")
        elif grep -Eq '(^| )(REPAIR|MODIFICATION|INSTALLATION|ARMHF TEST|X86) READY:' <<< "$output"; then
            ready+=("$COMPONENT")
        else
            installed+=("$COMPONENT")
        fi
    done

    printf '\n=== PLAIN-LANGUAGE SUMMARY ===\n'
    print_named_list 'Passed — already installed or currently valid:' "${installed[@]}"
    print_named_list 'Passed compatibility checks — ready to install:' "${ready[@]}"
    print_named_list 'Failed or blocked:' "${failed[@]}"
    print_named_list 'Skipped because they do not apply to this host:' "${skipped[@]}"
    printf 'Required installation order for this host:\n'
    for component in "${expected[@]}"; do
        index=$((index + 1))
        printf '  %d. %s\n' "$index" "$component"
    done
    if [[ ${#failed[@]} -gt 0 ]]; then
        printf 'RESULT: One or more checks are blocked or failed. Install prerequisites in the order above, then run --check all again.\n'
        return 1
    fi
    printf 'RESULT: Every applicable component is either already installed or ready to install.\n'
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
    local requested=$1
    if [[ $requested == all ]]; then
        check_all
    else
        check_one "$requested"
    fi
}

install_requested() {
    local requested=$1 component
    preflight_recorded_backups
    if [[ $requested == all ]]; then
        for component in "${COMPONENTS[@]}"; do
            if should_skip_all_component "$component"; then
                printf '\n=== SKIP: %s requires an ARM64 host ===\n' "$component"
                continue
            fi
            if component_is_recorded "$component"; then
                printf '\n=== SKIP: %s ===\nThis installation is already recorded by the manager; continuing from the next unrecorded component.\n' "$component"
                continue
            fi
            install_one "$component"
            if [[ $component == p25-nxdn-json ]]; then ensure_databases; fi
        done
    else
        if component_is_recorded "$requested"; then
            printf 'NOTICE: %s is already recorded as installed by this manager. No files changed.\n' "$requested"
            return
        fi
        install_one "$requested"
        if [[ $requested == p25-nxdn-json ]]; then ensure_databases; fi
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
        --reset-after-reinstall) [[ $# -eq 1 ]] || die "Unexpected arguments."; initialize_state; reset_after_reinstall ;;
        --help|-h) usage ;;
        "") usage; exit 2 ;;
        *) die "Unknown option: $1" ;;
    esac
}

main "$@"
