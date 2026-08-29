#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

# Add friendly P25 and NXDN reflector names to the locally installed
# DVSwitch Dashboard. This is an optional modification, not a repair.

set -Eeuo pipefail
umask 077

readonly SCRIPT_VERSION="1.1.1"
readonly FUNCTIONS_TARGET="/usr/share/dvswitch/include/functions.php"
readonly STATUS_TARGET="/usr/share/dvswitch/include/status.php"
readonly P25_JSON="/var/lib/mmdvm/P25Hosts.json"
readonly NXDN_JSON="/var/lib/mmdvm/NXDNHosts.json"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/p25-nxdn-friendly-names"
readonly SUPPORTED_FUNCTIONS_V1_HASH="7d1fa4c52ec2d4c5a9b25ded011cdb1990badd025579274aebe582d8f4611b10"
readonly SUPPORTED_FUNCTIONS_V2_HASH="840fcb4e8af7520c8f691fb108cb5b7f6146e38b13d3f1f7c751e0507eb737dd"
readonly SUPPORTED_STATUS_HASH="b573126d4d0ac54fdb8c331de6d75e260419f65a1d66fff6f711e4f7bfd0f2ab"
readonly FRIENDLY_STATUS_HASH="5b21a7a8e4e4a753ba3881bc3077ea4a1047c2e1d969cbd8f2b1c3a6c15976f3"
readonly DSTAR_STATUS_HASH="cdd063d6974e459fca279abc8c8ad6a112de89a6dbaa0fa92e03a1933b671831"
readonly DMR_V1_STATUS_HASH="c1a910a0f6e486f7e5077056a73208a8291e35a979897b4e250aeb492707fc64"
readonly DMR_V2_STATUS_HASH="3f2d81aad9fed503b38271fee033821d27aafea969ca6348fc0afc1c1a994d55"
readonly YSF_STATUS_HASH="d3ba63a6e57801697797e6a3ea747ec8def51cad9deb48054a48dfe436f34e09"
readonly MOD_MARKER="// DVSwitch-Mods: P25/NXDN friendly-name display v1"

WORK_DIR=""
ACTIVE_BACKUP=""
INSTALL_ACTIVE=0

die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
usage() { printf 'P25/NXDN dashboard friendly-name modification %s\nUsage: sudo %s {--check|--install|--restore BACKUP-NAME}\n' "$SCRIPT_VERSION" "$(basename "$0")"; }
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

validate_json() {
    REFLECTOR_JSON="$1" REFLECTOR_MODE="$2" python3 - <<'PY_JSON'
import json
import os
import sys

path = os.environ["REFLECTOR_JSON"]
mode = os.environ["REFLECTOR_MODE"]
try:
    with open(path, "r", encoding="utf-8-sig") as source:
        data = json.load(source)
    rows = data.get("reflectors") if isinstance(data, dict) else None
    if not isinstance(rows, list) or len(rows) < 200:
        raise ValueError("reflectors array is missing or undersized")
    seen = set()
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("reflector record is not an object")
        designator = row.get("designator")
        if type(designator) is not int or not 1 <= designator <= 9999999 or designator in seen:
            raise ValueError("invalid or duplicate designator")
        seen.add(designator)
        for field in ("name", "sponsor"):
            if row.get(field) is not None and not isinstance(row[field], str):
                raise ValueError("invalid " + field)
except Exception as exc:
    print(f"ERROR: {mode} dashboard JSON validation failed: {exc}", file=sys.stderr)
    sys.exit(1)
PY_JSON
}

patch_candidates() {
    FUNCTIONS_CANDIDATE="$WORK_DIR/functions.php" STATUS_CANDIDATE="$WORK_DIR/status.php" \
    DVS_SUPPORTED_FUNCTIONS_V1_HASH="$SUPPORTED_FUNCTIONS_V1_HASH" \
    DVS_SUPPORTED_FUNCTIONS_V2_HASH="$SUPPORTED_FUNCTIONS_V2_HASH" DVS_SUPPORTED_STATUS_HASH="$SUPPORTED_STATUS_HASH" \
    DVS_FRIENDLY_STATUS_HASH="$FRIENDLY_STATUS_HASH" DVS_DSTAR_STATUS_HASH="$DSTAR_STATUS_HASH" \
    DVS_DMR_V1_STATUS_HASH="$DMR_V1_STATUS_HASH" DVS_DMR_V2_STATUS_HASH="$DMR_V2_STATUS_HASH" \
    DVS_YSF_STATUS_HASH="$YSF_STATUS_HASH" \
    DVS_MOD_MARKER="$MOD_MARKER" python3 - <<'PY_PATCH'
from pathlib import Path
import hashlib
import os

functions_path = Path(os.environ["FUNCTIONS_CANDIDATE"])
status_path = Path(os.environ["STATUS_CANDIDATE"])
marker = os.environ["DVS_MOD_MARKER"]

php_function = r'''// DVSwitch-Mods: P25/NXDN friendly-name display v1
function formatReflectorLink($linkText, $mode) {
        if ($mode !== "P25" && $mode !== "NXDN") { return $linkText; }
        if (!preg_match('/(?:TG|reflector)\s*([0-9]+)/iu', strip_tags($linkText), $matches)) { return $linkText; }
        $number = $matches[1];
        $label = "";
        $jsonFile = "/var/lib/mmdvm/".$mode."Hosts.json";
        if (is_readable($jsonFile)) {
                $json = json_decode(file_get_contents($jsonFile), true);
                if (isset($json["reflectors"]) && is_array($json["reflectors"])) {
                        foreach ($json["reflectors"] as $reflector) {
                                if (!is_array($reflector) || !array_key_exists("designator", $reflector) || (string)$reflector["designator"] !== $number) { continue; }
                                foreach (array("name", "sponsor") as $field) {
                                        if (!array_key_exists($field, $reflector) || !is_string($reflector[$field])) { continue; }
                                        $candidate = preg_replace('/\s+/u', ' ', str_replace('_', ' ', trim($reflector[$field])));
                                        if (is_string($candidate) && $candidate !== "") { $label = $candidate; break; }
                                }
                                break;
                        }
                }
        }
        if ($label === "") { $label = "TG ".$number; }
        $label = htmlspecialchars($label, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8");
        return "Reflector<br/><span style=\"color:#b5651d;font-weight:bold;white-space:normal;word-break:normal;overflow-wrap:normal;text-align:center;\">".$label."</span>";
}

'''

function_anchor = "function getActualReflector("
p25_parser_v1 = 'preg_match("/Switched to reflector ([0-9]+)/", $logLine, $matches)'
p25_parser_v2 = 'preg_match("/(?:Switched|Statically linked) to reflector ([0-9]+)/", $logLine, $matches)'
repaired_filter_v1 = '"Link|Starting|Unlink|unlinking|Switched"'
repaired_filter_v2 = '"Link|Starting|Unlink|unlinking|Switched|Statically linked"'
p25_plain = 'getActualLink($logLinesP25Gateway, "P25")'
nxdn_plain = 'getActualLink($logLinesNXDNGateway, "NXDN")'
p25_wrapped = 'formatReflectorLink(getActualLink($logLinesP25Gateway, "P25"), "P25")'
nxdn_wrapped = 'formatReflectorLink(getActualLink($logLinesNXDNGateway, "NXDN"), "NXDN")'

def digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

def validate_functions_base(text):
    value = digest(text)
    if value == os.environ["DVS_SUPPORTED_FUNCTIONS_V1_HASH"]:
        expected = (text.count(p25_parser_v1), text.count(repaired_filter_v1), text.count(p25_parser_v2), text.count(repaired_filter_v2))
        if expected != (1, 2, 0, 0):
            raise SystemExit("ERROR: legacy P25 dashboard structure is missing or ambiguous: " + repr(expected))
    elif value == os.environ["DVS_SUPPORTED_FUNCTIONS_V2_HASH"]:
        expected = (text.count(p25_parser_v1), text.count(repaired_filter_v1), text.count(p25_parser_v2), text.count(repaired_filter_v2))
        if expected != (0, 0, 1, 2):
            raise SystemExit("ERROR: current P25 dashboard structure is missing or ambiguous: " + repr(expected))
    else:
        raise SystemExit("ERROR: unsupported functions.php base hash: " + value)

def require_markers(text, dstar, dmr_v1, dmr_v2, ysf):
    counts = (
        text.count("// DVSwitch-Mods: D-Star Tx TG/Ref display v1"),
        text.count("// DVSwitch-Mods: DMR Master friendly-name display v1"),
        text.count("// DVSwitch-Mods: DMR Master friendly-name display v2"),
        text.count("// DVSwitch-Mods: YSF dashboard null repair v1"),
    )
    if counts != (dstar, dmr_v1, dmr_v2, ysf):
        raise SystemExit("ERROR: downstream dashboard markers are missing or ambiguous: " + repr(counts))

def validate_modified_status(text, recovered):
    value = digest(text)
    if value == os.environ["DVS_FRIENDLY_STATUS_HASH"]:
        if digest(recovered) != os.environ["DVS_SUPPORTED_STATUS_HASH"]:
            raise SystemExit("ERROR: friendly-name status.php does not reverse to the supported stock file")
        require_markers(text, 0, 0, 0, 0)
    elif value == os.environ["DVS_DSTAR_STATUS_HASH"]:
        require_markers(text, 1, 0, 0, 0)
    elif value == os.environ["DVS_DMR_V1_STATUS_HASH"]:
        require_markers(text, 1, 1, 0, 0)
    elif value == os.environ["DVS_DMR_V2_STATUS_HASH"]:
        require_markers(text, 1, 0, 1, 0)
    elif value == os.environ["DVS_YSF_STATUS_HASH"]:
        require_markers(text, 1, 0, 1, 1)
    else:
        raise SystemExit("ERROR: unsupported modified status.php hash: " + value)

functions = functions_path.read_text(encoding="utf-8")
status = status_path.read_text(encoding="utf-8")
functions_markers = functions.count(marker)
status_wrappers = status.count("formatReflectorLink(")

if functions_markers == 0 and status_wrappers == 0:
    validate_functions_base(functions)
    if digest(status) != os.environ["DVS_SUPPORTED_STATUS_HASH"]:
        raise SystemExit("ERROR: unsupported unmodified status.php hash: " + digest(status))
    if functions.count(function_anchor) != 1 or "function formatReflectorLink(" in functions:
        raise SystemExit("ERROR: friendly-name insertion structure is missing or ambiguous")
    if status.count(p25_plain) != 1 or status.count(nxdn_plain) != 1:
        raise SystemExit("ERROR: dashboard status calls are missing or ambiguous")
    functions = functions.replace(function_anchor, php_function + function_anchor, 1)
    status = status.replace(p25_plain, p25_wrapped, 1).replace(nxdn_plain, nxdn_wrapped, 1)
elif functions_markers == 1 and status_wrappers == 2:
    if functions.count("function formatReflectorLink(") != 1 or functions.count(php_function) != 1:
        raise SystemExit("ERROR: modified functions.php is incomplete or ambiguous")
    if status.count(p25_wrapped) != 1 or status.count(nxdn_wrapped) != 1:
        raise SystemExit("ERROR: modified status.php is incomplete or ambiguous")
    if status.count(p25_plain) != 1 or status.count(nxdn_plain) != 1:
        raise SystemExit("ERROR: unexpected duplicate dashboard status calls")
    recovered_functions = functions.replace(php_function, "", 1)
    recovered_status = status.replace(p25_wrapped, p25_plain, 1).replace(nxdn_wrapped, nxdn_plain, 1)
    validate_functions_base(recovered_functions)
    validate_modified_status(status, recovered_status)
else:
    raise SystemExit(f"ERROR: partial or mixed friendly-name state (function_markers={functions_markers}, status_wrappers={status_wrappers})")

functions_path.write_text(functions, encoding="utf-8")
status_path.write_text(status, encoding="utf-8")
PY_PATCH
}

prepare_candidates() {
    WORK_DIR=$(mktemp -d /tmp/dvswitch-friendly-names.XXXXXX)
    cp -- "$FUNCTIONS_TARGET" "$WORK_DIR/functions.php"
    cp -- "$STATUS_TARGET" "$WORK_DIR/status.php"
    patch_candidates
    php -l "$WORK_DIR/functions.php" >/dev/null
    php -l "$WORK_DIR/status.php" >/dev/null
    local functions_hash status_hash
    functions_hash=$(file_hash "$WORK_DIR/functions.php")
    status_hash=$(file_hash "$WORK_DIR/status.php")
    patch_candidates
    [[ "$functions_hash" == "$(file_hash "$WORK_DIR/functions.php")" ]] || die "Embedded functions.php patch is not idempotent."
    [[ "$status_hash" == "$(file_hash "$WORK_DIR/status.php")" ]] || die "Embedded status.php patch is not idempotent."
}

begin_backup() {
    local timestamp candidate counter=0
    install -d -o root -g root -m 0700 "$BACKUP_ROOT"
    timestamp=$(date +%Y%m%d-%H%M%S)
    candidate="$BACKUP_ROOT/install-$timestamp"
    while [[ -e "$candidate" ]]; do counter=$((counter + 1)); candidate="$BACKUP_ROOT/install-$timestamp-$counter"; done
    install -d -o root -g root -m 0700 "$candidate"
    cp -a -- "$FUNCTIONS_TARGET" "$candidate/functions.php"
    cp -a -- "$STATUS_TARGET" "$candidate/status.php"
    ACTIVE_BACKUP="$candidate"
}

atomic_replace() {
    local candidate=$1 target=$2 temporary
    temporary=$(mktemp --tmpdir="$(dirname "$target")" .dvswitch-friendly-names.XXXXXX)
    cp -- "$candidate" "$temporary"
    chown --reference="$target" "$temporary"
    chmod --reference="$target" "$temporary"
    mv -fT -- "$temporary" "$target"
}

restore_backup_dir() {
    local directory=$1 functions_temporary status_temporary
    require_regular_file "$directory/functions.php"
    require_regular_file "$directory/status.php"
    functions_temporary=$(mktemp --tmpdir="$(dirname "$FUNCTIONS_TARGET")" .dvswitch-friendly-restore.XXXXXX)
    status_temporary=$(mktemp --tmpdir="$(dirname "$STATUS_TARGET")" .dvswitch-friendly-restore.XXXXXX)
    cp -a -- "$directory/functions.php" "$functions_temporary"
    cp -a -- "$directory/status.php" "$status_temporary"
    mv -fT -- "$functions_temporary" "$FUNCTIONS_TARGET"
    mv -fT -- "$status_temporary" "$STATUS_TARGET"
    php -l "$FUNCTIONS_TARGET" >/dev/null
    php -l "$STATUS_TARGET" >/dev/null
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
    for command in awk bash chmod chown cmp cp date grep install mktemp mv php python3 rm sha256sum; do require_command "$command"; done
    require_regular_file "$FUNCTIONS_TARGET"
    require_regular_file "$STATUS_TARGET"
}

preflight_install() {
    preflight_common
    require_regular_file "$P25_JSON"
    require_regular_file "$NXDN_JSON"
    php -l "$FUNCTIONS_TARGET" >/dev/null
    php -l "$STATUS_TARGET" >/dev/null
    validate_json "$P25_JSON" P25
    validate_json "$NXDN_JSON" NXDN
}

verify_installed() {
    cmp -s "$WORK_DIR/functions.php" "$FUNCTIONS_TARGET" || die "Installed functions.php does not match the validated candidate."
    cmp -s "$WORK_DIR/status.php" "$STATUS_TARGET" || die "Installed status.php does not match the validated candidate."
    php -l "$FUNCTIONS_TARGET" >/dev/null
    php -l "$STATUS_TARGET" >/dev/null
    [[ $(grep -Fc "$MOD_MARKER" "$FUNCTIONS_TARGET") -eq 1 ]] || die "Installed friendly-name marker is missing or duplicated."
    [[ $(grep -Fc 'formatReflectorLink(' "$STATUS_TARGET") -eq 2 ]] || die "Installed status wrappers are missing or duplicated."
    local parser_count
    parser_count=$(grep -Fc 'preg_match("/Switched to reflector ([0-9]+)/", $logLine, $matches)' "$FUNCTIONS_TARGET" || true)
    parser_count=$((parser_count + $(grep -Fc 'preg_match("/(?:Switched|Statically linked) to reflector ([0-9]+)/", $logLine, $matches)' "$FUNCTIONS_TARGET" || true)))
    [[ $parser_count -eq 1 ]] || die "Supported P25 parser was not preserved."
}

run_check() {
    preflight_install
    prepare_candidates
    if cmp -s "$FUNCTIONS_TARGET" "$WORK_DIR/functions.php" && cmp -s "$STATUS_TARGET" "$WORK_DIR/status.php"; then
        printf 'ALREADY MODIFIED: P25/NXDN dashboard friendly names are installed.\n'
    else
        printf 'MODIFICATION READY:\nBefore functions.php: %s\nAfter functions.php:  %s\nBefore status.php:    %s\nAfter status.php:     %s\n' "$(file_hash "$FUNCTIONS_TARGET")" "$(file_hash "$WORK_DIR/functions.php")" "$(file_hash "$STATUS_TARGET")" "$(file_hash "$WORK_DIR/status.php")"
    fi
    printf 'PASS: supported dashboard and JSON structure. No files changed.\n'
}

run_install() {
    preflight_install
    prepare_candidates
    if cmp -s "$FUNCTIONS_TARGET" "$WORK_DIR/functions.php" && cmp -s "$STATUS_TARGET" "$WORK_DIR/status.php"; then
        printf 'PASS: P25/NXDN dashboard friendly-name modification is already installed.\n'
        return
    fi
    begin_backup
    INSTALL_ACTIVE=1
    atomic_replace "$WORK_DIR/functions.php" "$FUNCTIONS_TARGET"
    atomic_replace "$WORK_DIR/status.php" "$STATUS_TARGET"
    verify_installed
    INSTALL_ACTIVE=0
    printf 'PASS: P25/NXDN dashboard friendly-name modification installed atomically.\nBackup: %s\n' "$ACTIVE_BACKUP"
}

run_restore() {
    local name=$1 directory
    preflight_common
    [[ "$name" =~ ^install-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] || die "Invalid backup name: $name"
    directory="$BACKUP_ROOT/$name"
    [[ -d "$directory" && ! -L "$directory" ]] || die "Protected backup not found: $name"
    restore_backup_dir "$directory"
    printf 'PASS: dashboard files restored from %s.\n' "$name"
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
