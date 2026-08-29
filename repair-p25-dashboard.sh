#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Repair P25 remote-command and static-startup link detection in the locally installed
# DVSwitch Dashboard functions.php. No upstream PHP file is distributed.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="0.5.0-dev"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PATCHER="$SCRIPT_DIR/lib/patch_p25_dashboard.py"
readonly TRANSACTION_LIBRARY="$SCRIPT_DIR/lib/transaction.sh"
readonly TARGET="/usr/share/dvswitch/include/functions.php"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/p25-dashboard"

WORK_DIR=""
INSTALL_ACTIVE=0

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
usage() { printf 'P25 dashboard compatibility repair %s\nUsage: sudo %s {--check|--dry-run|--install|--restore BACKUP-NAME}\n' "$SCRIPT_VERSION" "$(basename "$0")"; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
on_error() { local line=$1 status=$2; trap - ERR; set +e; printf 'ERROR: failed near line %s (status %s).\n' "$line" "$status" >&2; if [[ $INSTALL_ACTIVE -eq 1 ]]; then dvsm_transaction_rollback >&2 || printf 'ERROR: automatic rollback failed; use the protected backup.\n' >&2; fi; cleanup; exit "$status"; }
trap 'on_error $LINENO $?' ERR
trap cleanup EXIT

require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this repair with sudo."; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
check_regular_file() { [[ -f "$1" ]] || die "Required file not found: $1"; [[ ! -L "$1" ]] || die "Refusing symbolic-link target: $1"; }
check_os() { [[ -r /etc/os-release ]] || die "/etc/os-release is unavailable."; . /etc/os-release; [[ ${ID:-} == debian ]] || die "Unsupported OS: ${ID:-unknown}"; case "${VERSION_ID:-}" in 12|13);; *) die "Unsupported Debian version: ${VERSION_ID:-unknown}";; esac; }
preflight() { require_root; for command in bash cmp cp curl date install mktemp mv php python3 sha256sum stat systemctl; do require_command "$command"; done; check_os; check_regular_file "$PATCHER"; check_regular_file "$TRANSACTION_LIBRARY"; check_regular_file "$TARGET"; php -l "$TARGET" >/dev/null; python3 "$PATCHER" --help >/dev/null; }
prepare_candidate() { WORK_DIR=$(mktemp -d /tmp/dvswitch-p25-dashboard.XXXXXX); cp -- "$TARGET" "$WORK_DIR/functions.php"; python3 "$PATCHER" --functions "$WORK_DIR/functions.php"; php -l "$WORK_DIR/functions.php" >/dev/null; local first_hash; first_hash=$(sha256sum "$WORK_DIR/functions.php"); python3 "$PATCHER" --functions "$WORK_DIR/functions.php"; [[ "$first_hash" == "$(sha256sum "$WORK_DIR/functions.php")" ]] || die "Patcher is not idempotent on the candidate."; }
check_health() { local service http_code; for service in mmdvm_bridge p25gateway; do [[ $(systemctl is-active "$service") == active ]] || die "Service is not active: $service"; done; http_code=$(curl -ksS -o /dev/null -w '%{http_code}' https://127.0.0.1/dvswitch/); [[ "$http_code" == 200 ]] || die "Dashboard health check returned HTTP $http_code."; printf 'PASS: P25 services active and HTTPS dashboard returned 200.\n'; }
show_result() { if cmp -s "$TARGET" "$WORK_DIR/functions.php"; then printf 'ALREADY REPAIRED: %s\n' "$TARGET"; else printf 'REPAIR READY: %s\nBefore: ' "$TARGET"; sha256sum "$TARGET"; printf 'After:  '; sha256sum "$WORK_DIR/functions.php"; fi; }
run_check() { preflight; prepare_candidate; show_result; printf 'PASS: supported P25 dashboard structure. No files changed.\n'; }
run_dry_run() { run_check; }
run_install() { preflight; prepare_candidate; show_result; if cmp -s "$TARGET" "$WORK_DIR/functions.php"; then check_health; printf 'PASS: P25 dashboard compatibility repair is already installed.\n'; return; fi; . "$TRANSACTION_LIBRARY"; dvsm_transaction_begin "$BACKUP_ROOT"; dvsm_backup_file "$TARGET"; INSTALL_ACTIVE=1; dvsm_install_candidate "$WORK_DIR/functions.php" "$TARGET"; cmp -s "$WORK_DIR/functions.php" "$TARGET"; php -l "$TARGET" >/dev/null; python3 "$PATCHER" --functions "$TARGET"; cmp -s "$WORK_DIR/functions.php" "$TARGET"; check_health; INSTALL_ACTIVE=0; printf 'PASS: P25 dashboard compatibility repair installed atomically.\nBackup: %s\n' "$DVSM_TRANSACTION_DIR"; }
run_restore() { local name=$1; preflight; [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $name"; . "$TRANSACTION_LIBRARY"; dvsm_restore_backup_set "$BACKUP_ROOT/$name"; php -l "$TARGET" >/dev/null; check_health; printf 'PASS: functions.php restored from %s.\n' "$name"; }

main() { case "${1:-}" in --check) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_check;; --dry-run) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_dry_run;; --install) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_install;; --restore) [[ $# -eq 2 ]] || die "--restore requires one backup name."; run_restore "$2";; --help|-h) usage;; "") usage; exit 2;; *) die "Unknown option: $1";; esac; }
main "$@"
