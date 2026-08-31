#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Repair the DVSwitch Dashboard YSF Net card when YSFGateway's linked-name
# capitalization differs from YSFHosts.txt. Preserve the real linked name as
# the fallback instead of displaying the literal word "null".

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="1.0.3"
readonly TARGET="/usr/share/dvswitch/include/status.php"
readonly HOSTS_FILE="/var/lib/mmdvm/YSFHosts.txt"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/ysf-dashboard-null"
readonly SUPPORTED_HASH="3f2d81aad9fed503b38271fee033821d27aafea969ca6348fc0afc1c1a994d55"
readonly DMR_V4_YSF_STATUS_HASH="628c5b2debc3b658a132b2e3b10c1e656ff59f9e5412af4a15afc5bb7b292aee"
readonly DMR_V5_YSF_STATUS_HASH="02f4e7c6c5208d4f44bb559711cc006e0d8da7f4ad7ba5005ea47a4062330cf8"
readonly DMR_V6_YSF_STATUS_HASH="9c7f1749a37830d5adf51912c880d4c9faf6a79157bba249156f03f86e81b09d"
readonly REPAIR_MARKER="// DVSwitch-Mods: YSF dashboard null repair v1"
readonly DASHBOARD_URL="https://127.0.0.1/dvswitch/"

WORK_DIR=""
ACTIVE_BACKUP=""
INSTALL_ACTIVE=0

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
usage() { printf 'YSF dashboard null repair %s\nUsage: sudo %s {--check|--install|--restore BACKUP-NAME}\n' "$SCRIPT_VERSION" "$(basename "$0")"; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
require_regular_file() { [[ -f "$1" && ! -L "$1" ]] || die "Required regular non-symlink file not found: $1"; }
file_hash() { sha256sum "$1" | awk '{print $1}'; }

check_platform() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this repair with sudo."
    [[ -r /etc/os-release ]] || die "/etc/os-release is unavailable."
    . /etc/os-release
    [[ ${ID:-} == debian ]] || die "Unsupported OS: ${ID:-unknown}"
    case "${VERSION_ID:-}" in 12|13) ;; *) die "Unsupported Debian version: ${VERSION_ID:-unknown}" ;; esac
}

validate_hosts_file() {
    YSF_HOSTS="$HOSTS_FILE" python3 - <<'PY_HOSTS'
import os
import sys

path = os.environ["YSF_HOSTS"]
records = 0
try:
    with open(path, "r", encoding="utf-8-sig") as source:
        for raw in source:
            line = raw.rstrip("\r\n")
            if not line or line.startswith("#"):
                continue
            fields = line.split(";")
            if len(fields) < 5 or not fields[0].isdigit() or not fields[1].strip():
                raise ValueError("invalid host record")
            records += 1
    if records < 100:
        raise ValueError("too few host records")
except Exception as exc:
    print(f"ERROR: YSF host-file validation failed: {exc}", file=sys.stderr)
    sys.exit(1)
PY_HOSTS
}

patch_candidate() {
    STATUS_CANDIDATE="$WORK_DIR/status.php" DVS_SUPPORTED_HASH="$SUPPORTED_HASH" \
    DVS_DMR_V4_YSF_STATUS_HASH="$DMR_V4_YSF_STATUS_HASH" DVS_DMR_V5_YSF_STATUS_HASH="$DMR_V5_YSF_STATUS_HASH" \
    DVS_DMR_V6_YSF_STATUS_HASH="$DMR_V6_YSF_STATUS_HASH" \
    DVS_REPAIR_MARKER="$REPAIR_MARKER" python3 - <<'PY_PATCH'
from pathlib import Path
import hashlib
import os

path = Path(os.environ["STATUS_CANDIDATE"])
supported_hash = os.environ["DVS_SUPPORTED_HASH"]
marker = os.environ["DVS_REPAIR_MARKER"]
anchor = '        $ysfLinkedTo = getActualLink($reverseLogLinesYSFGateway, "YSF");'
old_fallback = '                $ysfLinkedToTxt = "null";'
new_fallback = '                $ysfLinkedToTxt = $ysfLinkedTo;'
old_match = '                        if (($ysfRoomTxtLine[0] == $ysfLinkedTo) || ($ysfRoomTxtLine[1] == $ysfLinkedTo)) {'
new_match = '                        if ((strcasecmp($ysfRoomTxtLine[0], $ysfLinkedTo) == 0) || (strcasecmp($ysfRoomTxtLine[1], $ysfLinkedTo) == 0)) {'

def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()

dmr_v2_marker = "// DVSwitch-Mods: DMR Master friendly-name display v2"
dmr_v3_marker = "// DVSwitch-Mods: DMR Master friendly-name display v3"
dmr_v2_output = '''                        echo "<tr><td  style=\\"background: #ffffed;\\" colspan=\\"2\\"><span style=\\"color:#b5651d;font-weight: bold\\">".dvsModsDmrMasterDisplay($dmrMasterHost, $abinfo)."</span></td></tr>\\n";}'''
dmr_v3_output = '''                        echo "<tr><td  style=\\"background: #ffffed;\\" colspan=\\"2\\"><span style=\\"color:#b5651d;font-weight:bold;white-space:normal;word-break:normal;overflow-wrap:anywhere;text-align:center;\\">".dvsModsDmrMasterDisplay($dmrMasterHost, $abinfo)."</span></td></tr>\\n";}'''

def supported_base(value):
    if digest(value) == supported_hash:
        return True
    counts = (value.count(dmr_v2_marker), value.count(dmr_v3_marker), value.count(dmr_v2_output), value.count(dmr_v3_output))
    if counts != (0, 1, 0, 1):
        return False
    v2_value = value.replace(dmr_v3_marker, dmr_v2_marker, 1).replace(dmr_v3_output, dmr_v2_output, 1)
    return digest(v2_value) == supported_hash

text = path.read_text(encoding="utf-8")
markers = text.count(marker)
if markers == 0:
    if not supported_base(text):
        raise SystemExit("ERROR: unsupported unmodified status.php hash: " + digest(text))
    counts = (text.count(anchor), text.count(old_fallback), text.count(new_fallback), text.count(old_match), text.count(new_match))
    if counts != (1, 1, 0, 1, 0):
        raise SystemExit("ERROR: unsupported or ambiguous YSF repair anchors: " + repr(counts))
    text = text.replace(anchor, marker + "\n" + anchor, 1)
    text = text.replace(old_fallback, new_fallback, 1)
    text = text.replace(old_match, new_match, 1)
elif markers == 1:
    counts = (text.count(anchor), text.count(old_fallback), text.count(new_fallback), text.count(old_match), text.count(new_match))
    if counts != (1, 0, 1, 0, 1):
        raise SystemExit("ERROR: incomplete or ambiguous YSF dashboard repair")
    recovered = text.replace(marker + "\n", "", 1).replace(new_fallback, old_fallback, 1).replace(new_match, old_match, 1)
    if digest(text) not in (os.environ["DVS_DMR_V4_YSF_STATUS_HASH"], os.environ["DVS_DMR_V5_YSF_STATUS_HASH"], os.environ["DVS_DMR_V6_YSF_STATUS_HASH"]) and not supported_base(recovered):
        raise SystemExit("ERROR: repaired status.php does not reverse to the supported dashboard file")
else:
    raise SystemExit("ERROR: duplicate YSF dashboard repair markers")

path.write_text(text, encoding="utf-8")
PY_PATCH
}

prepare_candidate() {
    WORK_DIR=$(mktemp -d /tmp/dvswitch-ysf-dashboard.XXXXXX)
    cp -- "$TARGET" "$WORK_DIR/status.php"
    patch_candidate
    php -l "$WORK_DIR/status.php" >/dev/null
    local first_hash
    first_hash=$(file_hash "$WORK_DIR/status.php")
    patch_candidate
    [[ "$first_hash" == "$(file_hash "$WORK_DIR/status.php")" ]] || die "Embedded repair is not idempotent."
}

begin_backup() {
    local timestamp candidate counter=0
    install -d -o root -g root -m 0700 "$BACKUP_ROOT"
    timestamp=$(date +%Y%m%d-%H%M%S)
    candidate="$BACKUP_ROOT/install-$timestamp"
    while [[ -e "$candidate" ]]; do counter=$((counter + 1)); candidate="$BACKUP_ROOT/install-$timestamp-$counter"; done
    install -d -o root -g root -m 0700 "$candidate"
    cp -a -- "$TARGET" "$candidate/status.php"
    ACTIVE_BACKUP="$candidate"
}

atomic_replace() {
    local temporary
    temporary=$(mktemp --tmpdir="$(dirname "$TARGET")" .dvswitch-ysf-dashboard.XXXXXX)
    cp -- "$WORK_DIR/status.php" "$temporary"
    chown --reference="$TARGET" "$temporary"
    chmod --reference="$TARGET" "$temporary"
    touch --reference="$TARGET" "$temporary"
    mv -fT -- "$temporary" "$TARGET"
}

dashboard_health() {
    systemctl is-active --quiet apache2.service || return 1
    [[ $(curl -ksS -o /dev/null -w '%{http_code}' --max-time 15 "$DASHBOARD_URL") == 200 ]]
}

reload_dashboard() {
    systemctl reload apache2.service
    dashboard_health
}

restore_backup_dir() {
    local directory=$1 temporary
    require_regular_file "$directory/status.php"
    php -l "$directory/status.php" >/dev/null
    temporary=$(mktemp --tmpdir="$(dirname "$TARGET")" .dvswitch-ysf-dashboard-restore.XXXXXX)
    cp -a -- "$directory/status.php" "$temporary"
    mv -fT -- "$temporary" "$TARGET"
    php -l "$TARGET" >/dev/null
    reload_dashboard
}

on_error() {
    local line=$1 status=$2
    trap - ERR
    set +e
    printf 'ERROR: failed near line %s (status %s).\n' "$line" "$status" >&2
    if [[ $INSTALL_ACTIVE -eq 1 && -n "$ACTIVE_BACKUP" ]]; then
        restore_backup_dir "$ACTIVE_BACKUP" && printf 'Automatic rollback completed.\n' >&2
    fi
    cleanup
    exit "$status"
}
trap 'on_error $LINENO $?' ERR
trap cleanup EXIT

preflight_common() {
    check_platform
    for command in awk chmod chown cmp cp curl date grep install mktemp mv php python3 rm sha256sum systemctl touch; do require_command "$command"; done
    require_regular_file "$TARGET"
    php -l "$TARGET" >/dev/null
    dashboard_health || die "Apache or the HTTPS dashboard is not healthy before the repair."
}

preflight_install() {
    preflight_common
    require_regular_file "$HOSTS_FILE"
    validate_hosts_file
}

verify_installed() {
    cmp -s "$WORK_DIR/status.php" "$TARGET" || { printf 'ERROR: installed status.php does not match the validated candidate.\n' >&2; return 1; }
    php -l "$TARGET" >/dev/null || return 1
    [[ $(grep -Fc "$REPAIR_MARKER" "$TARGET") -eq 1 ]] || return 1
    [[ $(grep -Fc 'strcasecmp($ysfRoomTxtLine[0], $ysfLinkedTo)' "$TARGET") -eq 1 ]] || return 1
    [[ $(grep -Fc '$ysfLinkedToTxt = $ysfLinkedTo;' "$TARGET") -eq 1 ]] || return 1
    local dmr_v2_count dmr_v3_count dmr_v4_count dmr_v5_count dmr_v6_count
    dmr_v2_count=$(grep -Fc '// DVSwitch-Mods: DMR Master friendly-name display v2' "$TARGET" || true)
    dmr_v3_count=$(grep -Fc '// DVSwitch-Mods: DMR Master friendly-name display v3' "$TARGET" || true)
    dmr_v4_count=$(grep -Fc '// DVSwitch-Mods: DMR Master friendly-name display v4' "$TARGET" || true)
    dmr_v5_count=$(grep -Fc '// DVSwitch-Mods: DMR Master friendly-name display v5' "$TARGET" || true)
    dmr_v6_count=$(grep -Fc '// DVSwitch-Mods: DMR Master friendly-name display v6' "$TARGET" || true)
    [[ $((dmr_v2_count + dmr_v3_count + dmr_v4_count + dmr_v5_count + dmr_v6_count)) -eq 1 ]] || return 1
    [[ $(grep -Fc '>Tx TG/Ref</th>' "$TARGET") -eq 2 ]] || return 1
    [[ $(grep -Fc 'formatReflectorLink(' "$TARGET") -eq 2 ]] || return 1
    dashboard_health
}

run_check() {
    preflight_install
    prepare_candidate
    if cmp -s "$TARGET" "$WORK_DIR/status.php"; then
        printf 'ALREADY REPAIRED: YSF dashboard null repair is installed.\n'
    else
        printf 'REPAIR READY: %s\nBefore: %s\nAfter:  %s\n' "$TARGET" "$(file_hash "$TARGET")" "$(file_hash "$WORK_DIR/status.php")"
        printf 'Planned correction: use case-insensitive YSF host matching and preserve the actual linked name as fallback.\n'
    fi
    printf 'PASS: exact dashboard version, YSF host data, and repair structure are supported. No files changed.\n'
}

run_install() {
    preflight_install
    prepare_candidate
    if cmp -s "$TARGET" "$WORK_DIR/status.php"; then
        verify_installed || die "Installed YSF dashboard repair failed validation."
        printf 'PASS: YSF dashboard null repair is already installed.\n'
        return
    fi
    begin_backup
    INSTALL_ACTIVE=1
    atomic_replace
    reload_dashboard
    verify_installed
    INSTALL_ACTIVE=0
    printf 'PASS: YSF dashboard null repair installed atomically.\nBackup: %s\n' "$ACTIVE_BACKUP"
}

run_restore() {
    local name=$1 directory
    preflight_common
    [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $name"
    directory="$BACKUP_ROOT/$name"
    [[ -d "$directory" && ! -L "$directory" ]] || die "Protected backup not found: $name"
    restore_backup_dir "$directory" || die "Protected backup restoration failed."
    printf 'PASS: YSF dashboard file restored from %s.\n' "$name"
}

main() {
    case "${1:-}" in
        --check) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_check ;;
        --install) [[ $# -eq 1 ]] || die "Unexpected arguments."; run_install ;;
        --restore) [[ $# -eq 2 ]] || die "--restore requires one backup name."; run_restore "$2" ;;
        --help|-h) usage ;;
        "") usage; exit 2 ;;
        *) die "Unknown option: $1" ;;
    esac
}
main "$@"
