#!/bin/bash

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

set -Eeuo pipefail

readonly SCRIPT_VERSION="0.1.0-dev"
readonly DASHBOARD_FUNCTIONS="/usr/share/dvswitch/include/functions.php"
readonly DASHBOARD_STATUS="/usr/share/dvswitch/include/status.php"
readonly DVSWITCH_SCRIPT="/opt/MMDVM_Bridge/dvswitch.sh"

usage() {
    printf 'DVSwitch Mods installer %s\n' "$SCRIPT_VERSION"
    printf 'Usage: sudo %s --check\n' "$(basename "$0")"
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

require_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this installer with sudo."
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

check_operating_system() {
    [[ -r /etc/os-release ]] || die "/etc/os-release is unavailable."

    # shellcheck disable=SC1091
    . /etc/os-release

    [[ ${ID:-} == "debian" ]] || die "Unsupported operating system: ${ID:-unknown}"

    case "${VERSION_ID:-}" in
        12|13) ;;
        *) die "Unsupported Debian version: ${VERSION_ID:-unknown}" ;;
    esac
}

check_regular_file() {
    local path=$1

    [[ -f "$path" ]] || die "Required file not found: $path"
    [[ ! -L "$path" ]] || die "Refusing symbolic-link target: $path"
}

run_preflight() {
    require_root
    require_command awk
    require_command cmp
    require_command cp
    require_command file
    require_command grep
    require_command install
    require_command mktemp
    require_command php
    require_command sha256sum
    require_command stat

    check_operating_system
    check_regular_file "$DASHBOARD_FUNCTIONS"
    check_regular_file "$DASHBOARD_STATUS"
    check_regular_file "$DVSWITCH_SCRIPT"

    php -l "$DASHBOARD_FUNCTIONS" >/dev/null || die "Existing functions.php failed PHP syntax validation."
    php -l "$DASHBOARD_STATUS" >/dev/null || die "Existing status.php failed PHP syntax validation."
    bash -n "$DVSWITCH_SCRIPT" || die "Existing dvswitch.sh failed shell syntax validation."

    printf 'PASS: supported Debian and DVSwitch installation detected.\n'
    printf 'PASS: existing PHP and shell files passed syntax validation.\n'
    printf 'No files were changed. Patch modules are not implemented yet.\n'
}

main() {
    case "${1:-}" in
        --check)
            [[ $# -eq 1 ]] || die "Unexpected arguments."
            run_preflight
            ;;
        --help|-h)
            usage
            ;;
        "")
            usage
            exit 2
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
}

main "$@"
