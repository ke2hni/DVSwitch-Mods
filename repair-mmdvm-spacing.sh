#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Repair supported malformed remote-command format strings in the locally
# installed MMDVM_Bridge executable. No upstream executable is distributed.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="1.1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PATCHER="$SCRIPT_DIR/lib/patch_mmdvm_binary.py"
readonly TRANSACTION_LIBRARY="$SCRIPT_DIR/lib/transaction.sh"
readonly TARGET="/opt/MMDVM_Bridge/MMDVM_Bridge"
readonly SERVICE="mmdvm_bridge.service"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/mmdvm-spacing"

WORK_DIR=""
INSTALL_ACTIVE=0

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
usage() { printf 'MMDVM spacing repair %s\nUsage: sudo %s {--check|--dry-run|--install|--restore BACKUP-NAME}\n' "$SCRIPT_VERSION" "$(basename "$0")"; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
on_error() { local line=$1 status=$2; trap - ERR; set +e; printf 'ERROR: failed near line %s (status %s).\n' "$line" "$status" >&2; if [[ $INSTALL_ACTIVE -eq 1 ]]; then dvsm_transaction_rollback >&2 || printf 'ERROR: automatic rollback failed; use the protected backup.\n' >&2; systemctl try-restart "$SERVICE" >/dev/null 2>&1 || true; fi; cleanup; exit "$status"; }
trap 'on_error $LINENO $?' ERR
trap cleanup EXIT

require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this repair with sudo."; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
check_regular_file() { [[ -f "$1" ]] || die "Required file not found: $1"; [[ ! -L "$1" ]] || die "Refusing symbolic-link target: $1"; }
preflight() { require_root; for command in bash cmp cp date file grep install mktemp mv python3 sha256sum stat systemctl; do require_command "$command"; done; check_regular_file "$PATCHER"; check_regular_file "$TRANSACTION_LIBRARY"; check_regular_file "$TARGET"; file -b "$TARGET" | grep -q ELF || die "MMDVM_Bridge is not an ELF executable."; systemctl cat "$SERVICE" >/dev/null; python3 "$PATCHER" --help >/dev/null; }
prepare_candidate() { WORK_DIR=$(mktemp -d /tmp/dvswitch-mmdvm-spacing.XXXXXX); cp -- "$TARGET" "$WORK_DIR/MMDVM_Bridge"; python3 "$PATCHER" --binary "$WORK_DIR/MMDVM_Bridge"; python3 "$PATCHER" --binary "$WORK_DIR/MMDVM_Bridge"; [[ $(stat -c '%s' "$TARGET") == "$(stat -c '%s' "$WORK_DIR/MMDVM_Bridge")" ]] || die "Candidate size changed."; }
show_result() { python3 "$PATCHER" --binary "$WORK_DIR/MMDVM_Bridge" --report; if cmp -s "$TARGET" "$WORK_DIR/MMDVM_Bridge"; then printf 'SUPPORTED REPAIRS ALREADY APPLIED: %s\n' "$TARGET"; else printf 'REPAIR READY: %s\nBefore: ' "$TARGET"; sha256sum "$TARGET"; printf 'After:  '; sha256sum "$WORK_DIR/MMDVM_Bridge"; fi; }
run_check() { preflight; prepare_candidate; show_result; printf 'PASS: supported amd64, i386, armhf, or arm64 MMDVM_Bridge pattern state. No files changed.\n'; }
run_dry_run() { run_check; }
run_install() { preflight; prepare_candidate; show_result; if cmp -s "$TARGET" "$WORK_DIR/MMDVM_Bridge"; then printf 'PASS: supported MMDVM spacing repairs are already installed.\n'; return; fi; . "$TRANSACTION_LIBRARY"; dvsm_transaction_begin "$BACKUP_ROOT"; dvsm_backup_file "$TARGET"; INSTALL_ACTIVE=1; dvsm_install_candidate "$WORK_DIR/MMDVM_Bridge" "$TARGET"; cmp -s "$WORK_DIR/MMDVM_Bridge" "$TARGET"; python3 "$PATCHER" --binary "$TARGET"; systemctl try-restart "$SERVICE"; systemctl is-active --quiet "$SERVICE"; INSTALL_ACTIVE=0; printf 'PASS: supported MMDVM spacing repairs installed atomically.\nBackup: %s\n' "$DVSM_TRANSACTION_DIR"; }
run_restore() { local name=$1; preflight; [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $name"; . "$TRANSACTION_LIBRARY"; dvsm_restore_backup_set "$BACKUP_ROOT/$name"; file -b "$TARGET" | grep -q ELF; systemctl try-restart "$SERVICE"; systemctl is-active --quiet "$SERVICE"; printf 'PASS: MMDVM_Bridge restored from %s.\n' "$name"; }

main() { case "${1:-}" in --check) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_check;; --dry-run) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_dry_run;; --install) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_install;; --restore) [[ $# -eq 2 ]] || die "--restore requires one backup name."; run_restore "$2";; --help|-h) usage;; "") usage; exit 2;; *) die "Unknown option: $1";; esac; }
main "$@"
