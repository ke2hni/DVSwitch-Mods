#!/bin/bash

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Transaction helpers for files already installed on the local system.

DVSM_TRANSACTION_DIR=""
declare -a DVSM_TRANSACTION_TARGETS=()
declare -a DVSM_TRANSACTION_BACKUPS=()
declare -a DVSM_TRANSACTION_EXISTED=()

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
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then chown root:root "$backup_root"; fi
    chmod 0700 "$backup_root"
    timestamp="$(date +%Y%m%d-%H%M%S)"
    candidate="$backup_root/install-$timestamp"
    while [[ -e "$candidate" ]]; do
        counter=$((counter + 1))
        candidate="$backup_root/install-$timestamp-$counter"
    done
    install -d -m 0700 "$candidate"
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then chown root:root "$candidate"; fi
    : > "$candidate/MANIFEST"
    chmod 0600 "$candidate/MANIFEST"

    DVSM_TRANSACTION_DIR=$candidate
    DVSM_TRANSACTION_TARGETS=()
    DVSM_TRANSACTION_BACKUPS=()
    DVSM_TRANSACTION_EXISTED=()
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
    DVSM_TRANSACTION_EXISTED+=(1)
    printf '1\t%s\t%s\n' "$target" "$backup" >> "$DVSM_TRANSACTION_DIR/MANIFEST"
}

dvsm_record_absent_file() {
    local target=$1
    [[ -n "$DVSM_TRANSACTION_DIR" ]] || { dvsm_transaction_error "transaction has not started"; return 1; }
    [[ ! -e "$target" && ! -L "$target" ]] || { dvsm_transaction_error "target is not absent: $target"; return 1; }
    for existing_target in "${DVSM_TRANSACTION_TARGETS[@]:-}"; do
        if [[ "$existing_target" == "$target" ]]; then
            dvsm_transaction_error "target already recorded: $target"
            return 1
        fi
    done
    DVSM_TRANSACTION_TARGETS+=("$target")
    DVSM_TRANSACTION_BACKUPS+=("")
    DVSM_TRANSACTION_EXISTED+=(0)
    printf '0\t%s\t-\n' "$target" >> "$DVSM_TRANSACTION_DIR/MANIFEST"
}

dvsm_restore_backup_set() {
    local backup_set=$1 existed target backup target_dir temporary
    [[ "$backup_set" == /* && -d "$backup_set" && ! -L "$backup_set" ]] || { dvsm_transaction_error "invalid backup set: $backup_set"; return 1; }
    [[ -f "$backup_set/MANIFEST" && ! -L "$backup_set/MANIFEST" ]] || { dvsm_transaction_error "manifest is unavailable: $backup_set"; return 1; }
    mapfile -t manifest_lines < "$backup_set/MANIFEST"
    for ((index=${#manifest_lines[@]} - 1; index >= 0; index--)); do
        IFS=$'\t' read -r existed target backup <<< "${manifest_lines[$index]}"
        [[ "$target" == /* && "$target" != *$'\n'* ]] || { dvsm_transaction_error "invalid manifest target"; return 1; }
        if [[ "$existed" == 0 ]]; then rm -f -- "$target"; continue; fi
        [[ "$existed" == 1 && -f "$backup" && ! -L "$backup" ]] || { dvsm_transaction_error "invalid manifest backup"; return 1; }
        target_dir=$(dirname "$target")
        temporary=$(mktemp --tmpdir="$target_dir" .dvswitch-mods-restore.XXXXXX)
        cp -a -- "$backup" "$temporary"
        mv -fT -- "$temporary" "$target"
    done
    printf 'Restored backup set: %s\n' "$backup_set"
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

dvsm_install_new_candidate() {
    local candidate=$1 target=$2 owner=${3:-root} group=${4:-root} mode=${5:-0644}
    local target_dir temporary
    [[ -f "$candidate" && ! -L "$candidate" ]] || { dvsm_transaction_error "candidate is not a regular file: $candidate"; return 1; }
    [[ ! -e "$target" && ! -L "$target" ]] || { dvsm_transaction_error "new target already exists: $target"; return 1; }
    target_dir=$(dirname "$target")
    temporary=$(mktemp --tmpdir="$target_dir" .dvswitch-mods.XXXXXX)
    install -o "$owner" -g "$group" -m "$mode" "$candidate" "$temporary"
    mv -fT -- "$temporary" "$target"
}

dvsm_transaction_rollback() {
    local index target backup target_dir temporary

    for ((index=${#DVSM_TRANSACTION_TARGETS[@]} - 1; index >= 0; index--)); do
        target=${DVSM_TRANSACTION_TARGETS[$index]}
        backup=${DVSM_TRANSACTION_BACKUPS[$index]}
        if [[ ${DVSM_TRANSACTION_EXISTED[$index]} -eq 0 ]]; then
            rm -f -- "$target"
            continue
        fi
        [[ -f "$backup" && ! -L "$backup" ]] || { dvsm_transaction_error "backup is unavailable: $backup"; return 1; }

        target_dir=$(dirname "$target")
        temporary=$(mktemp --tmpdir="$target_dir" .dvswitch-mods-restore.XXXXXX)
        cp -a -- "$backup" "$temporary"
        mv -fT -- "$temporary" "$target"
    done

    printf 'Rollback restored %d file(s).\n' "${#DVSM_TRANSACTION_TARGETS[@]}"
}
