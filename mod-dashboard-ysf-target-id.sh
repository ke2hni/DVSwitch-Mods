#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Add the YSF reflector TG number below its friendly name on the dashboard status card.
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
TARGET="/usr/share/dvswitch/include/status.php"
PATCHER="$SCRIPT_DIR/lib/patch_dashboard_ysf_target_id.py"
BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-ysf-target-id"
TRANSACTION_LIBRARY="$SCRIPT_DIR/lib/transaction.sh"
WORK_DIR=""
INSTALL_ACTIVE=0
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
rollback() {
    local status=$?
    if (( INSTALL_ACTIVE )); then dvsm_transaction_rollback || true; fi
    cleanup
    exit "$status"
}
trap rollback EXIT INT TERM HUP
prepare() {
    [[ -f "$TARGET" && ! -L "$TARGET" ]] || die "Required regular file not found: $TARGET"
    [[ -f "$PATCHER" && -f "$TRANSACTION_LIBRARY" ]] || die "Required installer files are missing."
    command -v python3 >/dev/null || die "python3 is required."
    command -v php >/dev/null || die "php is required."
    WORK_DIR="$(mktemp -d /tmp/dvswitch-ysf-target-id.XXXXXX)"
    cp -- "$TARGET" "$WORK_DIR/status.php"
    python3 "$PATCHER" "$WORK_DIR/status.php"
    php -l "$WORK_DIR/status.php" >/dev/null || die "PHP syntax validation failed."
    cp -- "$WORK_DIR/status.php" "$WORK_DIR/first.php"
    python3 "$PATCHER" "$WORK_DIR/status.php"
    cmp -s "$WORK_DIR/first.php" "$WORK_DIR/status.php" || die "YSF target-number patch is not idempotent."
}
if (($# == 0)); then die "Usage: sudo $0 {--check|--install|--restore BACKUP-NAME}"; fi
case "$1" in
    --check)
        [[ $# -eq 1 && $EUID -eq 0 ]] || die "Run with sudo: $0 --check"
        prepare
        if cmp -s "$TARGET" "$WORK_DIR/status.php"; then
            printf 'ALREADY MODIFIED: YSF status card shows the reflector TG number below its name.\n'
        else
            printf 'MODIFICATION READY: YSF status card will show the reflector TG number below its name.\n'
        fi
        printf 'PASS: supported YSF dashboard structure. No files changed.\n'
        ;;
    --install)
        [[ $# -eq 1 && $EUID -eq 0 ]] || die "Run with sudo: $0 --install"
        prepare
        if cmp -s "$TARGET" "$WORK_DIR/status.php"; then
            printf 'PASS: YSF reflector TG-number display is already installed; no backup created.\n'
            exit 0
        fi
        . "$TRANSACTION_LIBRARY"
        dvsm_transaction_begin "$BACKUP_ROOT"
        INSTALL_ACTIVE=1
        dvsm_backup_file "$TARGET"
        dvsm_install_candidate "$WORK_DIR/status.php" "$TARGET"
        php -l "$TARGET" >/dev/null || die "Installed PHP syntax validation failed."
        INSTALL_ACTIVE=0
        printf 'PASS: YSF reflector TG-number display installed atomically.\nBackup: %s\n' "$DVSM_TRANSACTION_DIR"
        ;;
    --restore)
        [[ $# -eq 2 && $EUID -eq 0 ]] || die "Run with sudo: $0 --restore BACKUP-NAME"
        . "$TRANSACTION_LIBRARY"
        dvsm_restore_backup_set "$BACKUP_ROOT/$2"
        ;;
    *)
        die "Usage: sudo $0 {--check|--install|--restore BACKUP-NAME}"
        ;;
esac
