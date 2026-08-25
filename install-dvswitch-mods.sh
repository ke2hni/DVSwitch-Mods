#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI
set -Eeuo pipefail
umask 077
readonly SCRIPT_VERSION="0.2.0-rc2"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PATCHER="$SCRIPT_DIR/lib/patch_p25_nxdn.py" TRANSACTION_LIBRARY="$SCRIPT_DIR/lib/transaction.sh"
readonly DASHBOARD_FUNCTIONS="/usr/share/dvswitch/include/functions.php" DASHBOARD_STATUS="/usr/share/dvswitch/include/status.php"
readonly DVSWITCH_SCRIPT="/opt/MMDVM_Bridge/dvswitch.sh" MMDVM_DIR="/var/lib/mmdvm" BACKUP_ROOT="/var/backups/dvswitch-mods"
readonly P25_JSON="$MMDVM_DIR/P25Hosts.json" NXDN_JSON="$MMDVM_DIR/NXDNHosts.json"
WORK_DIR=""; INSTALL_ACTIVE=0
die(){ printf 'ERROR: %s\n' "$1" >&2; exit 1; }
usage(){ printf 'DVSwitch Mods installer %s\nUsage: sudo %s {--check|--dry-run|--install|--restore BACKUP-NAME}\n' "$SCRIPT_VERSION" "$(basename "$0")"; }
cleanup(){ [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
on_error(){ local line=$1 status=$2; trap - ERR; set +e; printf 'ERROR: failed near line %s (status %s).\n' "$line" "$status" >&2; if [[ $INSTALL_ACTIVE -eq 1 ]]; then printf 'Restoring original files...\n' >&2; dvsm_transaction_rollback >&2 || printf 'ERROR: automatic rollback failed; use the protected backup.\n' >&2; fi; cleanup; exit "$status"; }
trap 'on_error $LINENO $?' ERR; trap cleanup EXIT
require_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this installer with sudo."; }
require_command(){ command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
check_regular_file(){ [[ -f "$1" ]] || die "Required file not found: $1"; [[ ! -L "$1" ]] || die "Refusing symbolic-link target: $1"; }
check_os(){ [[ -r /etc/os-release ]] || die "/etc/os-release is unavailable."; . /etc/os-release; [[ ${ID:-} == debian ]] || die "Unsupported OS: ${ID:-unknown}"; case "${VERSION_ID:-}" in 12|13);; *) die "Unsupported Debian version: ${VERSION_ID:-unknown}";; esac; }
preflight(){ require_root; for c in bash chmod chown cmp cp curl date file grep install mktemp mv php python3 sha256sum stat wc; do require_command "$c"; done; check_os; for f in "$PATCHER" "$TRANSACTION_LIBRARY" "$DASHBOARD_FUNCTIONS" "$DASHBOARD_STATUS" "$DVSWITCH_SCRIPT"; do check_regular_file "$f"; done; [[ -d "$MMDVM_DIR" && ! -L "$MMDVM_DIR" ]] || die "Invalid MMDVM directory."; php -l "$DASHBOARD_FUNCTIONS" >/dev/null; php -l "$DASHBOARD_STATUS" >/dev/null; bash -n "$DVSWITCH_SCRIPT"; python3 -m py_compile "$PATCHER"; }
validate_json(){ REFLECTOR_JSON="$1" REFLECTOR_MODE="$2" python3 - <<'PYJSON'
import json,os,sys
try:
 with open(os.environ['REFLECTOR_JSON'],encoding='utf-8') as f: data=json.load(f)
 rows=data.get('reflectors'); seen=set()
 if not isinstance(rows,list) or len(rows)<200: raise ValueError('missing or undersized reflectors array')
 for row in rows:
  if not isinstance(row,dict): raise ValueError('record is not an object')
  d,p=row.get('designator'),row.get('port')
  if not isinstance(d,int) or not 0<d<=65535 or d in seen: raise ValueError('invalid or duplicate designator')
  seen.add(d)
  if not isinstance(p,int) or not 0<p<=65535: raise ValueError('invalid port')
  for field in ('name','sponsor'):
   if row.get(field) is not None and not isinstance(row[field],str): raise ValueError('invalid '+field)
 if 10200 not in seen: raise ValueError('known reflector 10200 is missing')
 print('PASS: %s JSON validated (%d reflectors)'%(os.environ['REFLECTOR_MODE'],len(rows)))
except Exception as e: print('ERROR: JSON validation failed: %s'%e,file=sys.stderr); sys.exit(1)
PYJSON
}
download_json(){ curl --fail --location --silent --show-error --user-agent "DVSwitch" --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 2 -o "$2" "https://hostfiles.refcheck.radio/${1}Hosts.json"; validate_json "$2" "$1"; }
prepare_candidates(){ WORK_DIR=$(mktemp -d /tmp/dvswitch-mods.XXXXXX); cp -- "$DASHBOARD_FUNCTIONS" "$WORK_DIR/functions"; cp -- "$DASHBOARD_STATUS" "$WORK_DIR/status"; cp -- "$DVSWITCH_SCRIPT" "$WORK_DIR/dvswitch"; python3 "$PATCHER" --functions "$WORK_DIR/functions" --status "$WORK_DIR/status" --dvswitch "$WORK_DIR/dvswitch"; php -l "$WORK_DIR/functions" >/dev/null; php -l "$WORK_DIR/status" >/dev/null; bash -n "$WORK_DIR/dvswitch"; download_json P25 "$WORK_DIR/P25Hosts.json"; download_json NXDN "$WORK_DIR/NXDNHosts.json"; }
show_changes(){ for pair in "$DASHBOARD_FUNCTIONS:$WORK_DIR/functions" "$DASHBOARD_STATUS:$WORK_DIR/status" "$DVSWITCH_SCRIPT:$WORK_DIR/dvswitch"; do live=${pair%%:*}; candidate=${pair#*:}; if cmp -s "$live" "$candidate"; then printf 'UNCHANGED: %s\n' "$live"; else printf 'CHANGE READY: %s\n' "$live"; fi; done; printf 'JSON READY: %s and %s\n' "$P25_JSON" "$NXDN_JSON"; }
record_json(){ if [[ -e "$1" || -L "$1" ]]; then dvsm_backup_file "$1"; else dvsm_record_absent_file "$1"; fi; }
install_json(){ if [[ -e "$2" ]]; then dvsm_install_candidate "$1" "$2"; else dvsm_install_new_candidate "$1" "$2" root root 0644; fi; }
run_check(){ preflight; printf 'PASS: supported installation and syntax validated. No files changed.\n'; }
run_dry_run(){ preflight; prepare_candidates; show_changes; printf 'PASS: all candidates validated. No files changed.\n'; }
run_install(){ preflight; prepare_candidates; show_changes; . "$TRANSACTION_LIBRARY"; dvsm_transaction_begin "$BACKUP_ROOT"; dvsm_backup_file "$DASHBOARD_FUNCTIONS"; dvsm_backup_file "$DASHBOARD_STATUS"; dvsm_backup_file "$DVSWITCH_SCRIPT"; record_json "$P25_JSON"; record_json "$NXDN_JSON"; INSTALL_ACTIVE=1; dvsm_install_candidate "$WORK_DIR/functions" "$DASHBOARD_FUNCTIONS"; dvsm_install_candidate "$WORK_DIR/status" "$DASHBOARD_STATUS"; dvsm_install_candidate "$WORK_DIR/dvswitch" "$DVSWITCH_SCRIPT"; install_json "$WORK_DIR/P25Hosts.json" "$P25_JSON"; install_json "$WORK_DIR/NXDNHosts.json" "$NXDN_JSON"; php -l "$DASHBOARD_FUNCTIONS" >/dev/null; php -l "$DASHBOARD_STATUS" >/dev/null; bash -n "$DVSWITCH_SCRIPT"; validate_json "$P25_JSON" P25; validate_json "$NXDN_JSON" NXDN; INSTALL_ACTIVE=0; printf 'PASS: P25/NXDN module installed.\nBackup: %s\n' "$DVSM_TRANSACTION_DIR"; }
run_restore(){ local name=$1; preflight; [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $name"; . "$TRANSACTION_LIBRARY"; dvsm_restore_backup_set "$BACKUP_ROOT/$name"; php -l "$DASHBOARD_FUNCTIONS" >/dev/null; php -l "$DASHBOARD_STATUS" >/dev/null; bash -n "$DVSWITCH_SCRIPT"; printf 'PASS: restore validation completed.\n'; }
main(){ case "${1:-}" in --check) [[ $# -eq 1 ]]||die "Unexpected arguments."; run_check;; --dry-run) [[ $# -eq 1 ]]||die "Unexpected arguments."; run_dry_run;; --install) [[ $# -eq 1 ]]||die "Unexpected arguments."; run_install;; --restore) [[ $# -eq 2 ]]||die "--restore requires one backup name."; run_restore "$2";; --help|-h) usage;; "") usage; exit 2;; *) die "Unknown option: $1";; esac; }
main "$@"
