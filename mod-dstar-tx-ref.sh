#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Show the active D-Star reflector/module instead of talkgroup 0 in the
# DVSwitch Dashboard Analog Bridge card. This is an optional modification.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="0.1.0-dev"
readonly TARGET="/usr/share/dvswitch/include/status.php"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/dstar-tx-ref"
readonly SUPPORTED_HASH="5b21a7a8e4e4a753ba3881bc3077ea4a1047c2e1d969cbd8f2b1c3a6c15976f3"
readonly MOD_MARKER="// DVSwitch-Mods: D-Star Tx TG/Ref display v1"

WORK_DIR=""
ACTIVE_BACKUP=""
INSTALL_ACTIVE=0

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
usage() { printf 'D-Star Tx TG/Ref dashboard modification %s\nUsage: sudo %s {--check|--install|--restore BACKUP-NAME}\n' "$SCRIPT_VERSION" "$(basename "$0")"; }
cleanup() { [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
require_regular_file() { [[ -f "$1" && ! -L "$1" ]] || die "Required regular non-symlink file not found: $1"; }
file_hash() { sha256sum "$1" | awk '{print $1}'; }

check_platform() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run this modification with sudo."
    [[ -r /etc/os-release ]] || die "/etc/os-release is unavailable."
    . /etc/os-release
    [[ ${ID:-} == debian ]] || die "Unsupported OS: ${ID:-unknown}"
    case "${VERSION_ID:-}" in 12|13) ;; *) die "Unsupported Debian version: ${VERSION_ID:-unknown}" ;; esac
}

patch_candidate() {
    STATUS_CANDIDATE="$WORK_DIR/status.php" DVS_SUPPORTED_HASH="$SUPPORTED_HASH" DVS_MOD_MARKER="$MOD_MARKER" python3 - <<'PY_PATCH'
from pathlib import Path
import hashlib
import os

path = Path(os.environ["STATUS_CANDIDATE"])
supported_hash = os.environ["DVS_SUPPORTED_HASH"]
marker = os.environ["DVS_MOD_MARKER"]

insertion_anchor = "    $abinfo = getABInfo('/tmp/ABInfo_'.ABINFO.'.json');\n"
insertion = r'''    // DVSwitch-Mods: D-Star Tx TG/Ref display v1
    $txValue = $abinfo['digital']['tg'];
    if ($abinfo['tlv']['ambe_mode'] == "DSTAR") {
        $txValue = preg_replace('/^(Linked to|Linking to)\s+/i', '', trim(strip_tags(str_replace("<br />", " ", getDSTARLinks()))));
        $txValue = preg_replace('/\s*\(.*\)\s*$/', '', $txValue);
    }
'''

tooltip_old = '''    echo "<br>&nbsp;&nbsp;&nbsp;txTG: ".$abinfo['digital']['tg'];'''
tooltip_new = '''    echo "<br>&nbsp;&nbsp;&nbsp;txTG: ".$txValue;'''
row_old = '''    echo "<tr><th width=50%>Tx TG</th><td style=\\"background: #f9f9f9;font-weight: bold;color:#ef7215;\\">".$abinfo['digital']['tg']."</td></tr>\\n";'''
row_new = '''    echo "<tr><th width=50%>Tx TG/Ref</th><td style=\\"background: #f9f9f9;font-weight: bold;color:#ef7215;\\">".$txValue."</td></tr>\\n";'''

def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()

text = path.read_text(encoding="utf-8")
markers = text.count(marker)

if markers == 0:
    if digest(text) != supported_hash:
        raise SystemExit("ERROR: unsupported unmodified status.php hash: " + digest(text))
    counts = (text.count(insertion_anchor), text.count(tooltip_old), text.count(row_old))
    if counts != (1, 1, 2):
        raise SystemExit("ERROR: unsupported or ambiguous status.php anchors: " + repr(counts))
    if tooltip_new in text or row_new in text or "getDSTARLinks()" in text:
        raise SystemExit("ERROR: unexpected existing D-Star Tx display code")
    text = text.replace(insertion_anchor, insertion_anchor + insertion, 1)
    text = text.replace(tooltip_old, tooltip_new, 1)
    text = text.replace(row_old, row_new)
elif markers == 1:
    if text.count(insertion) != 1 or text.count(tooltip_new) != 1 or text.count(row_new) != 2:
        raise SystemExit("ERROR: incomplete or ambiguous D-Star Tx modification")
    if tooltip_old in text or row_old in text:
        raise SystemExit("ERROR: mixed D-Star Tx modification state")
    recovered = text.replace(insertion, "", 1).replace(tooltip_new, tooltip_old, 1).replace(row_new, row_old)
    if digest(recovered) != supported_hash:
        raise SystemExit("ERROR: modified status.php does not reverse to the supported Mod 2 file")
else:
    raise SystemExit("ERROR: duplicate D-Star Tx modification markers")

path.write_text(text, encoding="utf-8")
PY_PATCH
}

prepare_candidate() {
    WORK_DIR=$(mktemp -d /tmp/dvswitch-dstar-tx-ref.XXXXXX)
    cp -- "$TARGET" "$WORK_DIR/status.php"
    patch_candidate
    php -l "$WORK_DIR/status.php" >/dev/null
    local first_hash
    first_hash=$(file_hash "$WORK_DIR/status.php")
    patch_candidate
    [[ "$first_hash" == "$(file_hash "$WORK_DIR/status.php")" ]] || die "Embedded patch is not idempotent."
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
    temporary=$(mktemp --tmpdir="$(dirname "$TARGET")" .dvswitch-dstar-tx-ref.XXXXXX)
    cp -- "$WORK_DIR/status.php" "$temporary"
    chown --reference="$TARGET" "$temporary"
    chmod --reference="$TARGET" "$temporary"
    mv -fT -- "$temporary" "$TARGET"
}

restore_backup_dir() {
    local directory=$1 temporary
    require_regular_file "$directory/status.php"
    temporary=$(mktemp --tmpdir="$(dirname "$TARGET")" .dvswitch-dstar-tx-restore.XXXXXX)
    cp -a -- "$directory/status.php" "$temporary"
    mv -fT -- "$temporary" "$TARGET"
    php -l "$TARGET" >/dev/null
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

preflight() {
    check_platform
    for command in awk bash chmod chown cmp cp date grep install mktemp mv php python3 rm sha256sum; do require_command "$command"; done
    require_regular_file "$TARGET"
    php -l "$TARGET" >/dev/null
}

preflight_restore() {
    check_platform
    for command in cp mktemp mv php rm; do require_command "$command"; done
    require_regular_file "$TARGET"
}

verify_installed() {
    cmp -s "$WORK_DIR/status.php" "$TARGET" || die "Installed status.php does not match the validated candidate."
    php -l "$TARGET" >/dev/null
    [[ $(grep -Fc "$MOD_MARKER" "$TARGET") -eq 1 ]] || die "Installed modification marker is missing or duplicated."
    [[ $(grep -Fc 'Tx TG/Ref' "$TARGET") -eq 2 ]] || die "Installed Tx TG/Ref labels are missing or duplicated."
    [[ $(grep -Fc 'formatReflectorLink(' "$TARGET") -eq 2 ]] || die "P25/NXDN friendly-name wrappers were not preserved."
}

run_check() {
    preflight
    prepare_candidate
    if cmp -s "$TARGET" "$WORK_DIR/status.php"; then
        printf 'ALREADY MODIFIED: D-Star Tx TG/Ref display is installed.\n'
    else
        printf 'MODIFICATION READY:\nBefore status.php: %s\nAfter status.php:  %s\n' "$(file_hash "$TARGET")" "$(file_hash "$WORK_DIR/status.php")"
    fi
    printf 'PASS: supported dashboard structure. No files changed.\n'
}

run_install() {
    preflight
    prepare_candidate
    if cmp -s "$TARGET" "$WORK_DIR/status.php"; then
        printf 'PASS: D-Star Tx TG/Ref modification is already installed.\n'
        return
    fi
    begin_backup
    INSTALL_ACTIVE=1
    atomic_replace
    verify_installed
    INSTALL_ACTIVE=0
    printf 'PASS: D-Star Tx TG/Ref modification installed atomically.\nBackup: %s\n' "$ACTIVE_BACKUP"
}

run_restore() {
    local name=$1 directory
    preflight_restore
    [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $name"
    directory="$BACKUP_ROOT/$name"
    [[ -d "$directory" && ! -L "$directory" ]] || die "Protected backup not found: $name"
    restore_backup_dir "$directory"
    printf 'PASS: status.php restored from %s.\n' "$name"
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
