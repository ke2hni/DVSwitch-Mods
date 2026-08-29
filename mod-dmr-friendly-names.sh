#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Show the selected DMR talkgroup name in the DVSwitch Dashboard DMR Master
# card. BrandMeister data is also used for STFU. This is display-only.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="1.1.1"
readonly TARGET="/usr/share/dvswitch/include/status.php"
readonly BM_LIST="/var/lib/mmdvm/TGList_BM.txt"
readonly TGIF_LIST="/var/lib/mmdvm/TGList_TGIF.txt"
readonly STATE_FILE="/var/lib/mmdvm/dvswitch-mods-dmr-state.json"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/dmr-friendly-names"
readonly SUPPORTED_HASH="cdd063d6974e459fca279abc8c8ad6a112de89a6dbaa0fa92e03a1933b671831"
readonly SUPPORTED_V1_HASH="c1a910a0f6e486f7e5077056a73208a8291e35a979897b4e250aeb492707fc64"
readonly DMR_V2_STATUS_HASH="3f2d81aad9fed503b38271fee033821d27aafea969ca6348fc0afc1c1a994d55"
readonly YSF_STATUS_HASH="d3ba63a6e57801697797e6a3ea747ec8def51cad9deb48054a48dfe436f34e09"
readonly MOD_MARKER="// DVSwitch-Mods: DMR Master friendly-name display v2"

WORK_DIR=""
ACTIVE_BACKUP=""
INSTALL_ACTIVE=0

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
usage() { printf 'DMR Master friendly-name modification %s\nUsage: sudo %s {--check|--install|--restore BACKUP-NAME}\n' "$SCRIPT_VERSION" "$(basename "$0")"; }
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

validate_tg_list() {
    local file=$1 network=$2 minimum=$3 sentinel=$4
    TG_FILE="$file" TG_NETWORK="$network" TG_MINIMUM="$minimum" TG_SENTINEL="$sentinel" python3 - <<'PY_LIST'
import os
import sys

path = os.environ["TG_FILE"]
network = os.environ["TG_NETWORK"]
minimum = int(os.environ["TG_MINIMUM"])
sentinel = os.environ["TG_SENTINEL"]
seen = set()
try:
    with open(path, "r", encoding="utf-8-sig") as source:
        for raw in source:
            line = raw.rstrip("\r\n")
            if not line or line.startswith("#"):
                continue
            fields = line.split(";", 3)
            if len(fields) != 4 or not fields[0].isdigit() or fields[1] != "0":
                raise ValueError("invalid talkgroup record")
            number = int(fields[0])
            if not 1 <= number <= 9999999 or number in seen or not fields[2].strip():
                raise ValueError("invalid, duplicate, or unnamed talkgroup")
            if fields[3] != "TG" + fields[0]:
                raise ValueError("invalid description field")
            seen.add(number)
    if len(seen) < minimum or int(sentinel) not in seen:
        raise ValueError("talkgroup list failed sanity checks")
except Exception as exc:
    print(f"ERROR: {network} talkgroup list validation failed: {exc}", file=sys.stderr)
    sys.exit(1)
PY_LIST
}

validate_state_file() {
    [[ ! -e "$STATE_FILE" ]] && return 0
    require_regular_file "$STATE_FILE"
    DMR_STATE="$STATE_FILE" python3 - <<'PY_STATE'
import json
import os
import sys

try:
    with open(os.environ["DMR_STATE"], "r", encoding="utf-8") as source:
        state = json.load(source)
    if not isinstance(state, dict):
        raise ValueError("top level is not an object")
    for key, value in state.items():
        if key == "current_network":
            if value not in ("BM", "TGIF"):
                raise ValueError("invalid current network")
            continue
        if key not in ("BM", "TGIF") or not isinstance(value, dict):
            raise ValueError("invalid network state")
        tg = str(value.get("tg", ""))
        if not tg.isdigit() or tg == "0":
            raise ValueError("invalid saved talkgroup")
except Exception as exc:
    print(f"ERROR: DMR state validation failed: {exc}", file=sys.stderr)
    sys.exit(1)
PY_STATE
}

patch_candidate() {
    STATUS_CANDIDATE="$WORK_DIR/status.php" DVS_SUPPORTED_HASH="$SUPPORTED_HASH" DVS_SUPPORTED_V1_HASH="$SUPPORTED_V1_HASH" \
    DVS_DMR_V2_STATUS_HASH="$DMR_V2_STATUS_HASH" DVS_YSF_STATUS_HASH="$YSF_STATUS_HASH" DVS_MOD_MARKER="$MOD_MARKER" python3 - <<'PY_PATCH'
from pathlib import Path
import hashlib
import os

path = Path(os.environ["STATUS_CANDIDATE"])
supported_hash = os.environ["DVS_SUPPORTED_HASH"]
supported_v1_hash = os.environ["DVS_SUPPORTED_V1_HASH"]
marker = os.environ["DVS_MOD_MARKER"]
v1_marker = "// DVSwitch-Mods: DMR Master friendly-name display v1"

include_anchor = "include_once dirname(dirname(__FILE__)).'/include/functions.php';\n"
helper = r'''
// DVSwitch-Mods: DMR Master friendly-name display v2
function dvsModsDmrNetwork($master) {
        $master = strtoupper(str_replace('_', ' ', (string)$master));
        if (strpos($master, 'TGIF') !== false) { return 'TGIF'; }
        return 'BM';
}

function dvsModsDmrStateRead() {
        $file = '/var/lib/mmdvm/dvswitch-mods-dmr-state.json';
        if (!is_readable($file)) { return array(); }
        $state = json_decode(file_get_contents($file), true);
        return is_array($state) ? $state : array();
}

function dvsModsDmrStateWrite($state) {
        $file = '/var/lib/mmdvm/dvswitch-mods-dmr-state.json';
        $json = json_encode($state, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
        if ($json === false || !is_writable($file)) { return false; }
        return file_put_contents($file, $json."\n", LOCK_EX) !== false;
}

function dvsModsDmrTalkgroup($abinfo) {
        $values = array();
        if (isset($abinfo['last_tune'])) { $values[] = trim((string)$abinfo['last_tune']); }
        if (isset($abinfo['digital']['tg'])) { $values[] = trim((string)$abinfo['digital']['tg']); }
        foreach ($values as $value) {
                if (preg_match('/^(?:TG\s*)?([0-9]+)$/i', $value, $matches) && $matches[1] !== '0') { return $matches[1]; }
        }
        return '';
}

function dvsModsDmrName($network, $talkgroup) {
        $file = ($network === 'TGIF') ? '/var/lib/mmdvm/TGList_TGIF.txt' : '/var/lib/mmdvm/TGList_BM.txt';
        if (!is_readable($file)) { return ''; }
        $lines = file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        if (!is_array($lines)) { return ''; }
        foreach ($lines as $line) {
                if ($line === '' || strpos($line, '#') === 0) { continue; }
                $fields = explode(';', $line, 4);
                if (count($fields) === 4 && trim($fields[0]) === (string)$talkgroup && trim($fields[1]) === '0') {
                        $name = preg_replace('/\s+/u', ' ', str_replace('_', ' ', trim($fields[2])));
                        return is_string($name) ? $name : '';
                }
        }
        return '';
}

function dvsModsDmrMasterDisplay($master, $abinfo) {
        $state = dvsModsDmrStateRead();
        $mode = isset($abinfo['tlv']['ambe_mode']) ? strtoupper(trim((string)$abinfo['tlv']['ambe_mode'])) : '';
        $network = ($mode === 'STFU') ? 'BM' : dvsModsDmrNetwork($master);
        if ($mode === 'DMR' || $mode === 'STFU') {
                $talkgroup = dvsModsDmrTalkgroup($abinfo);
                if ($talkgroup !== '' && !($mode === 'DMR' && $network === 'TGIF' && $talkgroup === '9')) {
                        $state[$network] = array('tg' => $talkgroup);
                        $state['current_network'] = $network;
                        dvsModsDmrStateWrite($state);
                }
        } else if (isset($state['current_network']) && ($state['current_network'] === 'BM' || $state['current_network'] === 'TGIF')) {
                $network = $state['current_network'];
        }
        $talkgroup = '';
        if (isset($state[$network]) && is_array($state[$network]) && isset($state[$network]['tg'])) {
                $candidate = trim((string)$state[$network]['tg']);
                if (preg_match('/^[0-9]+$/', $candidate) && $candidate !== '0') { $talkgroup = $candidate; }
        }
        if ($talkgroup === '' && ($mode === 'DMR' || $mode === 'STFU')) { $talkgroup = dvsModsDmrTalkgroup($abinfo); }
        if ($talkgroup === '') { return htmlspecialchars((string)$master, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }
        $name = dvsModsDmrName($network, $talkgroup);
        $display = ($name !== '') ? $name : 'TG '.$talkgroup;
        return htmlspecialchars($display, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

'''

old_output = '''                        echo "<tr><td  style=\\"background: #ffffed;\\" colspan=\\"2\\"><span style=\\"color:#b5651d;font-weight: bold\\">".$dmrMasterHost."</span></td></tr>\\n";}'''
new_output = '''                        echo "<tr><td  style=\\"background: #ffffed;\\" colspan=\\"2\\"><span style=\\"color:#b5651d;font-weight: bold\\">".dvsModsDmrMasterDisplay($dmrMasterHost, $abinfo)."</span></td></tr>\\n";}'''

def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()

text = path.read_text(encoding="utf-8")
markers = text.count(marker)
v1_markers = text.count(v1_marker)

old_logic = r'''        $network = dvsModsDmrNetwork($master);
        if ($mode === 'DMR') {
                $talkgroup = dvsModsDmrTalkgroup($abinfo);
                if ($talkgroup !== '' && !($network === 'TGIF' && $talkgroup === '9')) {'''
new_logic = r'''        $network = ($mode === 'STFU') ? 'BM' : dvsModsDmrNetwork($master);
        if ($mode === 'DMR' || $mode === 'STFU') {
                $talkgroup = dvsModsDmrTalkgroup($abinfo);
                if ($talkgroup !== '' && !($mode === 'DMR' && $network === 'TGIF' && $talkgroup === '9')) {'''
old_fallback = "        if ($talkgroup === '' && $mode === 'DMR') { $talkgroup = dvsModsDmrTalkgroup($abinfo); }"
new_fallback = "        if ($talkgroup === '' && ($mode === 'DMR' || $mode === 'STFU')) { $talkgroup = dvsModsDmrTalkgroup($abinfo); }"

if markers == 0 and v1_markers == 0:
    if digest(text) != supported_hash:
        raise SystemExit("ERROR: unsupported unmodified status.php hash: " + digest(text))
    counts = (text.count(include_anchor), text.count(old_output), text.count(new_output))
    if counts != (1, 1, 0):
        raise SystemExit("ERROR: unsupported or ambiguous DMR Master anchors: " + repr(counts))
    if 'function dvsModsDmrMasterDisplay(' in text:
        raise SystemExit("ERROR: unexpected existing DMR friendly-name code")
    text = text.replace(include_anchor, include_anchor + helper, 1)
    text = text.replace(old_output, new_output, 1)
elif markers == 0 and v1_markers == 1:
    if digest(text) != supported_v1_hash:
        raise SystemExit("ERROR: unsupported or altered v1 status.php hash: " + digest(text))
    counts = (text.count(old_logic), text.count(new_logic), text.count(old_fallback), text.count(new_fallback))
    if counts != (1, 0, 1, 0):
        raise SystemExit("ERROR: incomplete or ambiguous v1 STFU upgrade anchors: " + repr(counts))
    text = text.replace(v1_marker, marker, 1)
    text = text.replace(old_logic, new_logic, 1)
    text = text.replace(old_fallback, new_fallback, 1)
elif markers == 1 and v1_markers == 0:
    if text.count(helper) != 1 or text.count(new_output) != 1 or text.count(old_output) != 0:
        raise SystemExit("ERROR: incomplete or ambiguous DMR friendly-name modification")
    recovered = text.replace(helper, '', 1).replace(new_output, old_output, 1)
    value = digest(text)
    if value == os.environ["DVS_DMR_V2_STATUS_HASH"]:
        if digest(recovered) != supported_hash:
            raise SystemExit("ERROR: DMR status.php does not reverse to the supported D-Star file")
        if text.count("// DVSwitch-Mods: YSF dashboard null repair v1") != 0:
            raise SystemExit("ERROR: unexpected YSF marker in DMR-only dashboard state")
    elif value == os.environ["DVS_YSF_STATUS_HASH"]:
        if text.count("// DVSwitch-Mods: YSF dashboard null repair v1") != 1:
            raise SystemExit("ERROR: final dashboard YSF marker is missing or ambiguous")
    else:
        raise SystemExit("ERROR: unsupported modified status.php hash: " + value)
else:
    raise SystemExit("ERROR: duplicate or mixed DMR friendly-name modification markers")

path.write_text(text, encoding="utf-8")
PY_PATCH
}

prepare_candidate() {
    WORK_DIR=$(mktemp -d /tmp/dvswitch-dmr-friendly.XXXXXX)
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
    if [[ -e "$STATE_FILE" ]]; then
        require_regular_file "$STATE_FILE"
        cp -a -- "$STATE_FILE" "$candidate/dmr-state.json"
    else
        : > "$candidate/state-was-absent"
    fi
    ACTIVE_BACKUP="$candidate"
}

prepare_state() {
    if [[ -e "$STATE_FILE" ]]; then
        require_regular_file "$STATE_FILE"
        validate_state_file
        chown root:www-data "$STATE_FILE"
        chmod 0664 "$STATE_FILE"
    else
        printf '{}\n' > "$STATE_FILE"
        chown root:www-data "$STATE_FILE"
        chmod 0664 "$STATE_FILE"
    fi
}

atomic_replace() {
    local temporary
    temporary=$(mktemp --tmpdir="$(dirname "$TARGET")" .dvswitch-dmr-friendly.XXXXXX)
    cp -- "$WORK_DIR/status.php" "$temporary"
    chown --reference="$TARGET" "$temporary"
    chmod --reference="$TARGET" "$temporary"
    mv -fT -- "$temporary" "$TARGET"
}

restore_backup_dir() {
    local directory=$1 temporary state_temporary
    require_regular_file "$directory/status.php"
    temporary=$(mktemp --tmpdir="$(dirname "$TARGET")" .dvswitch-dmr-friendly-restore.XXXXXX)
    cp -a -- "$directory/status.php" "$temporary"
    mv -fT -- "$temporary" "$TARGET"
    if [[ -f "$directory/dmr-state.json" && ! -L "$directory/dmr-state.json" ]]; then
        state_temporary=$(mktemp --tmpdir="$(dirname "$STATE_FILE")" .dvswitch-dmr-state-restore.XXXXXX)
        cp -a -- "$directory/dmr-state.json" "$state_temporary"
        mv -fT -- "$state_temporary" "$STATE_FILE"
    elif [[ -f "$directory/state-was-absent" && ! -L "$directory/state-was-absent" ]]; then
        rm -f -- "$STATE_FILE"
    else
        return 1
    fi
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

preflight_common() {
    check_platform
    for command in awk bash chmod chown cmp cp date getent grep install mktemp mv php python3 rm sha256sum; do require_command "$command"; done
    require_regular_file "$TARGET"
    getent group www-data >/dev/null || die "Required group not found: www-data"
    php -l "$TARGET" >/dev/null
}

preflight_install() {
    preflight_common
    require_regular_file "$BM_LIST"
    require_regular_file "$TGIF_LIST"
    validate_tg_list "$BM_LIST" BrandMeister 1000 3100
    validate_tg_list "$TGIF_LIST" TGIF 100 31665
    validate_state_file
}

verify_installed() {
    if ! cmp -s "$WORK_DIR/status.php" "$TARGET"; then printf 'ERROR: installed status.php does not match the validated candidate.\n' >&2; return 1; fi
    if ! php -l "$TARGET" >/dev/null; then printf 'ERROR: installed status.php failed PHP syntax validation.\n' >&2; return 1; fi
    if [[ $(grep -Fc "$MOD_MARKER" "$TARGET") -ne 1 ]]; then printf 'ERROR: installed modification marker is missing or duplicated.\n' >&2; return 1; fi
    if [[ $(grep -Fc 'dvsModsDmrMasterDisplay($dmrMasterHost, $abinfo)' "$TARGET") -ne 1 ]]; then printf 'ERROR: DMR Master display wrapper is missing or duplicated.\n' >&2; return 1; fi
    if [[ $(grep -Fc '>Tx TG/Ref</th>' "$TARGET") -ne 2 ]]; then printf 'ERROR: D-Star Tx TG/Ref labels were not preserved.\n' >&2; return 1; fi
    if [[ $(grep -Fc 'formatReflectorLink(' "$TARGET") -ne 2 ]]; then printf 'ERROR: P25/NXDN friendly-name wrappers were not preserved.\n' >&2; return 1; fi
    if [[ ! -f "$STATE_FILE" || -L "$STATE_FILE" ]]; then printf 'ERROR: DMR state file is missing or unsafe.\n' >&2; return 1; fi
    [[ $(stat -c '%U:%G:%a' "$STATE_FILE") == root:www-data:664 ]] || { printf 'ERROR: DMR state file metadata is incorrect.\n' >&2; return 1; }
    if ! validate_state_file; then printf 'ERROR: DMR state file validation failed.\n' >&2; return 1; fi
}

run_check() {
    preflight_install
    prepare_candidate
    if cmp -s "$TARGET" "$WORK_DIR/status.php"; then
        printf 'ALREADY MODIFIED: DMR Master friendly-name display is installed.\n'
    else
        printf 'MODIFICATION READY:\nBefore status.php: %s\nAfter status.php:  %s\n' "$(file_hash "$TARGET")" "$(file_hash "$WORK_DIR/status.php")"
    fi
    printf 'PASS: supported dashboard and DMR talkgroup-list structure. No files changed.\n'
}

run_install() {
    preflight_install
    prepare_candidate
    if cmp -s "$TARGET" "$WORK_DIR/status.php"; then
        verify_installed
        printf 'PASS: DMR Master friendly-name modification is already installed.\n'
        return
    fi
    begin_backup
    INSTALL_ACTIVE=1
    prepare_state
    atomic_replace
    if ! verify_installed; then
        if restore_backup_dir "$ACTIVE_BACKUP"; then
            INSTALL_ACTIVE=0
            die "Installation validation failed; automatic rollback completed."
        fi
        die "Installation validation failed and automatic rollback failed; use the protected backup."
    fi
    INSTALL_ACTIVE=0
    printf 'PASS: DMR Master friendly-name modification installed atomically.\nBackup: %s\n' "$ACTIVE_BACKUP"
}

run_restore() {
    local name=$1 directory
    preflight_common
    [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $name"
    directory="$BACKUP_ROOT/$name"
    [[ -d "$directory" && ! -L "$directory" ]] || die "Protected backup not found: $name"
    restore_backup_dir "$directory" || die "Protected backup is incomplete or restoration failed."
    printf 'PASS: DMR dashboard files restored from %s.\n' "$name"
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
