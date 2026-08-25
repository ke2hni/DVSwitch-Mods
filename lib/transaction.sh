#!/bin/bash

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Transaction helpers for files already installed on the local system.

DVSM_TRANSACTION_DIR=""
declare -a DVSM_TRANSACTION_TARGETS=()
declare -a DVSM_TRANSACTION_BACKUPS=()

dvsm_transaction_error() {
    printf 'TRANSACTION ERROR: %s\n' "$1" >&2
    return 1
}

dvsm_require_regular_target() {
    local target=$1
    [[ -f "$target" ]] || { dvsm_transaction_error "target is not a regular file: $target"; return 1; }
    [[ ! -L "$target" ]] || { dvsm_transaction_error "refusing symbolic-link target: $target"; return 1; }
}

dvsm_transaction_begin() {
    local backup_root=$1 timestamp candidate counter=0

    [[ "$backup_root" == /* ]] || { dvsm_transaction_error "backup root must be absolute"; return 1; }
    [[ ! -L "$backup_root" ]] || { dvsm_transaction_error "backup root must not be a symbolic link"; return 1; }

    install -d -m 0700 "$backup_root"
    timestamp="$(date +%Y%m%d-%H%M%S)"
    candidate="$backup_root/install-$timestamp"
    while [[ -e "$candidate" ]]; do
        counter=$((counter + 1))
        candidate="$backup_root/install-$timestamp-$counter"
    done
    install -d -m 0700 "$candidate"

    DVSM_TRANSACTION_DIR=$candidate
    DVSM_TRANSACTION_TARGETS=()
    DVSM_TRANSACTION_BACKUPS=()
    printf 'Backup set: %s\n' "$DVSM_TRANSACTION_DIR"
}

dvsm_backup_file() {
    local target=$1 index backup

    [[ -n "$DVSM_TRANSACTION_DIR" ]] || { dvsm_transaction_error "transaction has not started"; return 1; }
    dvsm_require_regular_target "$target" || return 1

    for existing_target in "${DVSM_TRANSACTION_TARGETS[@]:-}"; do
        if [[ "$existing_target" == "$target" ]]; then
            dvsm_transaction_error "target already backed up: $target"
            return 1
        fi
    done

    index=$(printf '%04d' "$((${#DVSM_TRANSACTION_TARGETS[@]} + 1))")
    backup="$DVSM_TRANSACTION_DIR/$index-$(basename "$target")"
    cp -a -- "$target" "$backup"

    DVSM_TRANSACTION_TARGETS+=("$target")
    DVSM_TRANSACTION_BACKUPS+=("$backup")
}

dvsm_install_candidate() {
    local candidate=$1 target=$2 target_dir temporary

    [[ -f "$candidate" && ! -L "$candidate" ]] || { dvsm_transaction_error "candidate is not a regular file: $candidate"; return 1; }
    dvsm_require_regular_target "$target" || return 1

    target_dir=$(dirname "$target")
    temporary=$(mktemp --tmpdir="$target_dir" .dvswitch-mods.XXXXXX)
    cp -- "$candidate" "$temporary"
    chown --reference="$target" "$temporary"
    chmod --reference="$target" "$temporary"
    mv -fT -- "$temporary" "$target"
}

dvsm_transaction_rollback() {
    local index target backup target_dir temporary

    for ((index=${#DVSM_TRANSACTION_TARGETS[@]} - 1; index >= 0; index--)); do
        target=${DVSM_TRANSACTION_TARGETS[$index]}
        backup=${DVSM_TRANSACTION_BACKUPS[$index]}
        [[ -f "$backup" && ! -L "$backup" ]] || { dvsm_transaction_error "backup is unavailable: $backup"; return 1; }

        target_dir=$(dirname "$target")
        temporary=$(mktemp --tmpdir="$target_dir" .dvswitch-mods-restore.XXXXXX)
        cp -a -- "$backup" "$temporary"
        mv -fT -- "$temporary" "$target"
    done

    printf 'Rollback restored %d file(s).\n' "${#DVSM_TRANSACTION_TARGETS[@]}"
}
