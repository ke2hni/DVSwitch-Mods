#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Architecture-selecting front end for the separate MMDVM_Bridge repairs.

set -Eeuo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TARGET="/opt/MMDVM_Bridge/MMDVM_Bridge"

SELECTED_SCRIPT=""
SELECTED_NAME=""
BACKUP_ROOT=""

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
usage() {
    printf '%s\n' \
        "MMDVM spacing repair manager $SCRIPT_VERSION" \
        "Usage: sudo $(basename "$0") {--identify|--check|--dry-run|--install|--list-backups|--uninstall BACKUP-NAME}"
}

require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this operation with sudo."; }
require_regular() { [[ -f "$1" && ! -L "$1" ]] || die "Required regular file is unavailable: $1"; }

select_repair() {
    local description
    require_regular "$TARGET"
    command -v file >/dev/null 2>&1 || die "Required command not found: file"
    description=$(file -b "$TARGET")
    case "$description" in
        *"ELF 64-bit"*"ARM aarch64"*)
            SELECTED_NAME="arm64"
            SELECTED_SCRIPT="$SCRIPT_DIR/repair-mmdvm-spacing.sh"
            BACKUP_ROOT="/var/backups/dvswitch-mods/mmdvm-spacing"
            ;;
        *"ELF 32-bit"*"ARM"*"EABI5"*"hard-float"*)
            SELECTED_NAME="armhf"
            SELECTED_SCRIPT="$SCRIPT_DIR/repair-mmdvm-spacing-armhf.sh"
            BACKUP_ROOT="/var/backups/dvswitch-mods/mmdvm-spacing-armhf"
            ;;
        *"ELF 64-bit"*"x86-64"*)
            SELECTED_NAME="amd64"
            SELECTED_SCRIPT="$SCRIPT_DIR/repair-mmdvm-spacing-x86.sh"
            BACKUP_ROOT="/var/backups/dvswitch-mods/mmdvm-spacing-x86"
            ;;
        *"ELF 32-bit"*"Intel 80386"*|*"ELF 32-bit"*"Intel i386"*)
            SELECTED_NAME="i386"
            SELECTED_SCRIPT="$SCRIPT_DIR/repair-mmdvm-spacing-x86.sh"
            BACKUP_ROOT="/var/backups/dvswitch-mods/mmdvm-spacing-x86"
            ;;
        *) die "Unsupported MMDVM_Bridge architecture: $description" ;;
    esac
    require_regular "$SELECTED_SCRIPT"
    [[ -x "$SELECTED_SCRIPT" ]] || die "Selected repair is not executable: $SELECTED_SCRIPT"
}

show_selection() {
    select_repair
    printf 'Architecture: %s\nRepair: %s\nBackup root: %s\n' \
        "$SELECTED_NAME" "$(basename "$SELECTED_SCRIPT")" "$BACKUP_ROOT"
}

list_backups() {
    require_root
    select_repair
    printf 'Architecture: %s\nBackup root: %s\n' "$SELECTED_NAME" "$BACKUP_ROOT"
    if [[ ! -d "$BACKUP_ROOT" ]]; then
        printf 'No installation backups found.\n'
        return
    fi
    find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'install-*' -printf '%f\n' | sort
}

delegate() {
    local operation=$1
    require_root
    select_repair
    printf 'Detected %s; using %s.\n' "$SELECTED_NAME" "$(basename "$SELECTED_SCRIPT")"
    "$SELECTED_SCRIPT" "$operation"
}

uninstall_repair() {
    local backup=$1 backup_dir backup_file manifest existed target stored backup_description backup_arch="" found=0
    require_root
    select_repair
    [[ "$backup" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $backup"
    backup_dir="$BACKUP_ROOT/$backup"
    backup_file="$backup_dir/0001-MMDVM_Bridge"
    manifest="$backup_dir/MANIFEST"
    [[ -d "$backup_dir" && ! -L "$backup_dir" ]] || die "Backup not found for $SELECTED_NAME: $backup"
    require_regular "$backup_file"
    require_regular "$manifest"
    while IFS=$'\t' read -r existed target stored; do
        if [[ "$existed" == 1 && "$target" == "$TARGET" && "$stored" == "$backup_file" ]]; then found=1; fi
    done < "$manifest"
    [[ $found -eq 1 ]] || die "Backup manifest does not contain the exact MMDVM_Bridge target."
    backup_description=$(file -b "$backup_file")
    case "$backup_description" in
        *"ELF 64-bit"*"ARM aarch64"*) backup_arch="arm64" ;;
        *"ELF 32-bit"*"ARM"*"EABI5"*"hard-float"*) backup_arch="armhf" ;;
        *"ELF 64-bit"*"x86-64"*) backup_arch="amd64" ;;
        *"ELF 32-bit"*"Intel 80386"*|*"ELF 32-bit"*"Intel i386"*) backup_arch="i386" ;;
        *) die "Backup does not contain a supported MMDVM_Bridge executable." ;;
    esac
    [[ "$backup_arch" == "$SELECTED_NAME" ]] || die "Backup architecture $backup_arch does not match installed architecture $SELECTED_NAME."
    printf 'Detected %s; restoring its protected pre-install backup.\n' "$SELECTED_NAME"
    "$SELECTED_SCRIPT" --restore "$backup"
    printf 'PASS: %s MMDVM spacing repair uninstalled using %s.\n' "$SELECTED_NAME" "$backup"
}

main() {
    case "${1:-}" in
        --identify) [[ $# -eq 1 ]] || die "Unexpected arguments."; show_selection ;;
        --check) [[ $# -eq 1 ]] || die "Unexpected arguments."; delegate --check ;;
        --dry-run) [[ $# -eq 1 ]] || die "Unexpected arguments."; delegate --dry-run ;;
        --install) [[ $# -eq 1 ]] || die "Unexpected arguments."; delegate --install ;;
        --list-backups) [[ $# -eq 1 ]] || die "Unexpected arguments."; list_backups ;;
        --uninstall) [[ $# -eq 2 ]] || die "--uninstall requires one backup name."; uninstall_repair "$2" ;;
        --help|-h) usage ;;
        "") usage; exit 2 ;;
        *) die "Unknown option: $1" ;;
    esac
}

main "$@"
