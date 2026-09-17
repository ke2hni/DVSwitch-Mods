#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI
set -Eeuo pipefail
umask 077
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TARGET="/usr/share/dvswitch/include/functions.php"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-duration"
readonly TRANSACTION_LIBRARY="$SCRIPT_DIR/lib/transaction.sh"
WORK_DIR=""; INSTALL_ACTIVE=0
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
on_error() { local line=$1 status=$2; trap - ERR; set +e; printf 'ERROR: failed near line %s (status %s).\n' "$line" "$status" >&2; if ((INSTALL_ACTIVE)); then dvsm_transaction_rollback >&2 || true; fi; cleanup; exit "$status"; }
trap 'on_error $LINENO $?' ERR; trap cleanup EXIT
require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die 'Run this repair with sudo.'; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
require_file() { [[ -f "$1" && ! -L "$1" ]] || die "Required regular file is unavailable: $1"; }
prepare_candidate() {
    WORK_DIR=$(mktemp -d /tmp/dvswitch-dashboard-duration.XXXXXX); cp -- "$TARGET" "$WORK_DIR/functions.php"
    python3 - "$WORK_DIR/functions.php" <<'PY'
import re, sys
from pathlib import Path
path = Path(sys.argv[1]); text = path.read_text(encoding='utf-8')
marker = '// DVSwitch-Mods: dashboard duration type repair v2'
if text.count(marker) > 1: raise SystemExit('ERROR: ambiguous dashboard duration repair')
if marker in text or re.search(r'ceil\s*\(\s*\(float\)\s*\$listElem\[6\]\s*\)', text): raise SystemExit(0)
pattern = re.compile(r'''(?P<indent>\s*)\$timestamp->add\(new DateInterval\(\s*'PT'\s*\.\s*ceil\(\s*\$listElem\[6\]\s*\)\s*\.\s*'S'\s*\)\s*\);''')
match = pattern.search(text)
if not match: raise SystemExit('ERROR: stock duration target not found')
replacement = (match.group('indent') + '// ' + marker + '\n' + match.group('indent') + 'if (!is_numeric($listElem[6])) { return $mode; }\n' + match.group(0).replace('ceil($listElem[6])', 'ceil((float)$listElem[6])'))
path.write_text(text[:match.start()] + replacement + text[match.end():], encoding='utf-8')
PY
}
preflight() { require_root; for command in bash cmp cp php python3 mktemp; do require_command "$command"; done; require_file "$TARGET"; require_file "$TRANSACTION_LIBRARY"; php -l "$TARGET" >/dev/null; }
run_check() { preflight; prepare_candidate; php -l "$WORK_DIR/functions.php" >/dev/null; if cmp -s "$TARGET" "$WORK_DIR/functions.php"; then printf 'ALREADY REPAIRED: dashboard duration handling is installed.\n'; else printf 'READY: dashboard duration repair available; no files changed.\n'; fi; }
run_install() { preflight; prepare_candidate; php -l "$WORK_DIR/functions.php" >/dev/null; if cmp -s "$TARGET" "$WORK_DIR/functions.php"; then printf 'ALREADY REPAIRED: dashboard duration handling is installed.\n'; return; fi; . "$TRANSACTION_LIBRARY"; dvsm_transaction_begin "$BACKUP_ROOT"; dvsm_backup_file "$TARGET"; INSTALL_ACTIVE=1; dvsm_install_candidate "$WORK_DIR/functions.php" "$TARGET"; php -l "$TARGET" >/dev/null; INSTALL_ACTIVE=0; printf 'PASS: dashboard duration repair installed. Backup: %s\n' "$DVSM_TRANSACTION_DIR"; }
run_restore() { require_root; . "$TRANSACTION_LIBRARY"; dvsm_restore_backup_set "$BACKUP_ROOT/$1"; php -l "$TARGET" >/dev/null; printf 'PASS: dashboard duration repair restored from %s.\n' "$1"; }
main() { case "${1:-}" in --check) run_check;; --install) run_install;; --restore) [[ $# -eq 2 ]] || die '--restore requires one backup name.'; run_restore "$2";; --help|-h) printf 'Dashboard duration repair %s\n' "$SCRIPT_VERSION";; *) die "Usage: sudo $(basename "$0") {--check|--install|--restore BACKUP-NAME}";; esac; }
main "$@"
