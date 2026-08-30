#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

"""Patch a temporary local copy of the DVSwitch TXT database updater."""

from __future__ import annotations

import argparse
from pathlib import Path


class PatchError(RuntimeError):
    pass


MARKER = "# DVSwitch-Mods: safe TXT database updater repair"


SAFE_UPDATER = r'''# DVSwitch-Mods: safe TXT database updater repair
#################################################################
# Install a validated database candidate while retaining metadata.
#################################################################
function installValidatedDatabase() {
    declare _candidate="$1" _live="$2"

    if [ -e "${_live}" ]; then
        chown --reference="${_live}" "${_candidate}" || return 1
        chmod --reference="${_live}" "${_candidate}" || return 1
    else
        chown root:root "${_candidate}" || return 1
        chmod 0644 "${_candidate}" || return 1
    fi

    mv -f -- "${_candidate}" "${_live}"
}

#################################################################
# Download, validate, and atomically install a TXT database.
#################################################################
function downloadAndValidateDatabase() {
    declare _name="$1" _url="$2" _kind="$3" _marker="${4:-}"
    declare _live="${MMDVM_DIR}/${_name}" _raw _candidate
    declare _fileSize=0 _recordCount=0

    _raw=$(mktemp "${MMDVM_DIR}/.${_name}.download.XXXXXX") || {
        echo "Error, unable to create temporary file for ${_name}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    }
    _candidate="${_raw}"

    if ! ${DEBUG} curl --fail --location --silent --show-error \
        --user-agent "DVSwitch" --connect-timeout 10 --max-time 60 \
        --retry 3 --retry-delay 2 -o "${_raw}" "${_url}"; then
        echo "Warning, ${_name} download failure; keeping existing ${_name}"
        rm -f -- "${_raw}"
        _ERRORCODE=$ERROR_FILE_NOT_FOUND
        return
    fi

    if [ ! -s "${_raw}" ]; then
        echo "Error, downloaded ${_name} is empty; keeping existing file"
        rm -f -- "${_raw}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if grep -Eqi '<!doctype|<html|<body' "${_raw}"; then
        echo "Error, downloaded ${_name} appears to contain HTML; keeping existing file"
        rm -f -- "${_raw}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    case "${_kind}" in
        TGIF)
            _candidate=$(mktemp "${MMDVM_DIR}/.${_name}.candidate.XXXXXX") || {
                rm -f -- "${_raw}"
                _ERRORCODE=$ERROR_INVALID_FILE
                return
            }
            if ! TGIF_RAW="${_raw}" TGIF_OUT="${_candidate}" python3 - <<'PY_TGIF'
import csv
import os
import sys

rows = {}
try:
    with open(os.environ["TGIF_RAW"], "r", encoding="utf-8-sig", newline="") as src:
        for row in csv.reader(src):
            if len(row) < 2:
                continue
            tg, name = row[0].strip(), row[1].strip()
            if not tg.isdigit() or not name:
                continue
            name = " ".join(name.replace(";", ",").replace("\r", " ").replace("\n", " ").split())
            if name:
                rows[int(tg)] = name
    if len(rows) < 100 or 101 not in rows or 31665 not in rows:
        raise ValueError("TGIF response failed sanity checks")
    with open(os.environ["TGIF_OUT"], "w", encoding="utf-8", newline="\n") as dst:
        dst.write("# ID;Option;Name;Description\n")
        dst.write("# Source: https://api.tgif.network/dmr/talkgroups/csv\n")
        for tg in sorted(rows):
            dst.write(f"{tg};0;{rows[tg]};TG{tg}\n")
except Exception as exc:
    print(f"TGIF database conversion failed: {exc}", file=sys.stderr)
    sys.exit(1)
PY_TGIF
            then
                rm -f -- "${_raw}" "${_candidate}"
                _ERRORCODE=$ERROR_INVALID_FILE
                return
            fi
            rm -f -- "${_raw}"
            ;;
        BM)
            _candidate=$(mktemp "${MMDVM_DIR}/.${_name}.candidate.XXXXXX") || {
                rm -f -- "${_raw}"
                _ERRORCODE=$ERROR_INVALID_FILE
                return
            }
            if ! BM_RAW="${_raw}" BM_OUT="${_candidate}" python3 - <<'PY_BM'
import json
import os
import sys

records = {}

def add(tg, name):
    tg = str(tg).strip() if tg is not None else ""
    name = str(name).strip() if name is not None else ""
    if not tg.isdigit() or not name:
        return
    number = int(tg)
    if not 1 <= number <= 9999999:
        return
    name = " ".join(name.replace(";", ",").replace("\r", " ").replace("\n", " ").split())
    if name:
        records[number] = name

def parse(item, fallback=None):
    if isinstance(item, str):
        add(fallback, item)
    elif isinstance(item, dict):
        tg = next((item[k] for k in ("ID", "id", "TalkGroup", "talkgroup", "tgid", "group") if k in item), fallback)
        name = next((item[k] for k in ("Name", "name", "Description", "description") if k in item), None)
        add(tg, name)

try:
    with open(os.environ["BM_RAW"], "r", encoding="utf-8-sig") as src:
        data = json.load(src)
    if isinstance(data, list):
        for item in data:
            parse(item)
    elif isinstance(data, dict):
        wrapped = next((data[k] for k in ("talkgroups", "data", "results") if isinstance(data.get(k), list)), None)
        if wrapped is not None:
            for item in wrapped:
                parse(item)
        else:
            for key, value in data.items():
                if str(key).strip().isdigit():
                    parse(value, key)
    if len(records) < 1000 or 91 not in records or 3100 not in records:
        raise ValueError("BrandMeister response failed sanity checks")
    with open(os.environ["BM_OUT"], "w", encoding="utf-8", newline="\n") as dst:
        dst.write("# ID;Option;Name;Description\n# Option: TG:0, REF:1, PC:2\n")
        for tg in sorted(records):
            dst.write(f"{tg};0;{records[tg]};TG{tg}\n")
except Exception as exc:
    print(f"BrandMeister database conversion failed: {exc}", file=sys.stderr)
    sys.exit(1)
PY_BM
            then
                rm -f -- "${_raw}" "${_candidate}"
                _ERRORCODE=$ERROR_INVALID_FILE
                return
            fi
            rm -f -- "${_raw}"
            ;;
    esac

    _fileSize=$(wc -c < "${_candidate}")
    case "${_kind}" in
        YSF) _recordCount=$(awk -F';' '$1 ~ /^[0-9][0-9][0-9][0-9][0-9]$/ && NF >= 5 && $2 != "" && $4 != "" && $5 ~ /^[0-9]+$/ {c++} END {print c+0}' "${_candidate}"); (( _fileSize >= 10000 && _recordCount >= 500 )) ;;
        P25) _recordCount=$(awk '!/^[[:space:]]*(#|$)/ && NF >= 3 && $1 ~ /^[0-9]+$/ && $2 != "" && $3 ~ /^[0-9]+$/ {c++} END {print c+0}' "${_candidate}"); (( _fileSize >= 500 && _recordCount >= 20 )) ;;
        NXDN) _recordCount=$(awk '!/^[[:space:]]*(#|$)/ && NF >= 3 && $1 ~ /^[0-9]+$/ && $2 != "" && $3 ~ /^[0-9]+$/ {c++} END {print c+0}' "${_candidate}"); (( _fileSize >= 500 && _recordCount >= 20 )) && awk '$1 == 65000 {ok=1} END {exit(ok ? 0 : 1)}' "${_candidate}" ;;
        TGIF) _recordCount=$(awk -F';' '$1 ~ /^[0-9]+$/ && $2 == 0 && $4 == "TG"$1 {c++} END {print c+0}' "${_candidate}"); (( _fileSize >= 1000 && _recordCount >= 100 )) ;;
        BM) _recordCount=$(awk -F';' '$1 ~ /^[0-9]+$/ && $2 == 0 && $4 == "TG"$1 {c++} END {print c+0}' "${_candidate}"); (( _fileSize >= 20000 && _recordCount >= 1000 )) ;;
        DCS) _recordCount=$(awk '$1 ~ /^DCS[0-9A-Z]{3}$/ && NF >= 2 {c++} END {print c+0}' "${_candidate}"); (( _fileSize >= 500 && _recordCount >= 20 )) ;;
        DPLUS) _recordCount=$(awk '$1 ~ /^REF[0-9A-Z]{3}$/ && NF >= 2 {c++} END {print c+0}' "${_candidate}"); (( _fileSize >= 500 && _recordCount >= 20 )) ;;
        DEXTRA) _recordCount=$(awk '$1 ~ /^XRF[0-9A-Z]{3}$/ && NF >= 2 {c++} END {print c+0}' "${_candidate}"); (( _fileSize >= 500 && _recordCount >= 20 )) ;;
        XLX) _recordCount=$(awk -F';' '$1 ~ /^[0-9A-Z][0-9A-Z][0-9A-Z]$/ && NF >= 2 && $2 != "" {c++} END {print c+0}' "${_candidate}"); (( _fileSize >= 500 && _recordCount >= 20 )) ;;
        GENERIC) grep -Fq -- "${_marker}" "${_candidate}" ;;
        *) false ;;
    esac
    if (( $? != 0 )); then
        echo "Error, downloaded ${_name} failed ${_kind} validation; keeping existing file"
        rm -f -- "${_candidate}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if ! installValidatedDatabase "${_candidate}" "${_live}"; then
        echo "Error, unable to install validated ${_name}"
        rm -f -- "${_candidate}"
        _ERRORCODE=$ERROR_INVALID_FILE
        return
    fi

    if [ "${_kind}" = GENERIC ]; then
        echo "${_name} downloaded and validated successfully (${_fileSize} bytes)"
    else
        echo "${_name} downloaded and validated successfully (${_recordCount} records, ${_fileSize} bytes)"
    fi
}

#################################################################
# Compatibility wrapper for remaining stock Pi-Star TXT feeds.
#################################################################
function downloadAndValidate() {
    downloadAndValidateDatabase "$1" "https://www.pistar.uk/downloads/$2" GENERIC "$3"
}

'''


STOCK_FUNCTION_START = "function downloadAndValidate() {\n"
DATABASE_FUNCTION_START = "function downloadDatabases() {\n"

STOCK_CALLS = '''        downloadAndValidate "NXDNHosts.txt" "NXDN_Hosts.txt" "dvswitch.org"
        downloadAndValidate "P25Hosts.txt" "P25_Hosts.txt" "dvswitch.org"
        downloadAndValidate "TGList_BM.txt" "TGList_BM.txt" "DVSWITCH"
        downloadAndValidate "YSFHosts.txt" "YSF_Hosts.txt" "dvswitch.org"

        downloadAndValidate "TGList_TGIF.txt" "TGList_TGIF.txt" "TGIF"
'''

REPAIRED_CALLS = '''        downloadAndValidateDatabase "NXDNHosts.txt" "https://hostfiles.refcheck.radio/NXDNHosts.txt" NXDN
        downloadAndValidateDatabase "P25Hosts.txt" "https://hostfiles.refcheck.radio/P25Hosts.txt" P25
        downloadAndValidateDatabase "TGList_BM.txt" "https://api.brandmeister.network/v2/talkgroup" BM
        downloadAndValidateDatabase "YSFHosts.txt" "https://hostfiles.refcheck.radio/YSFHosts.txt" YSF

        downloadAndValidateDatabase "TGList_TGIF.txt" "https://api.tgif.network/dmr/talkgroups/csv" TGIF
'''

STOCK_DSTAR_CALLS = '''        downloadAndValidate "DCS_Hosts.txt" "DCS_Hosts.txt" "DCS006"
        downloadAndValidate "DPlus_Hosts.txt" "DPlus_Hosts.txt" "REF030"
        downloadAndValidate "DExtra_Hosts.txt" "DExtra_Hosts.txt" "XRF012"
        downloadAndValidate "XLXHosts.txt" "XLXHosts.txt" "001;"
'''

REPAIRED_DSTAR_CALLS = '''        downloadAndValidateDatabase "DCS_Hosts.txt" "https://www.pistar.uk/downloads/DCS_Hosts.txt" DCS
        downloadAndValidateDatabase "DPlus_Hosts.txt" "https://www.pistar.uk/downloads/DPlus_Hosts.txt" DPLUS
        downloadAndValidateDatabase "DExtra_Hosts.txt" "https://www.pistar.uk/downloads/DExtra_Hosts.txt" DEXTRA
        downloadAndValidateDatabase "XLXHosts.txt" "https://hostfiles.refcheck.radio/XLXHosts.txt" XLX
'''


def section(text: str, start: str, end: str) -> tuple[str, str, str]:
    if text.count(start) != 1 or text.count(end) != 1:
        raise PatchError(f"expected one {start.strip()} and one {end.strip()}")
    before, remainder = text.split(start, 1)
    middle, after = remainder.split(end, 1)
    return before, start + middle, end + after


def patch_text(text: str) -> str:
    marker_count = text.count(MARKER)
    stock_count = text.count(STOCK_FUNCTION_START)

    if marker_count == 1:
        repaired_calls_valid = all(
            text.count(call) == 1
            for call in REPAIRED_CALLS.splitlines()
            if call.strip()
        )
        if stock_count != 1 or not repaired_calls_valid or text.count(REPAIRED_DSTAR_CALLS) != 1:
            raise PatchError("incomplete or ambiguous repaired updater")
        if STOCK_CALLS in text or STOCK_DSTAR_CALLS in text:
            raise PatchError("mixed stock and repaired updater calls")
        return text
    if marker_count != 0:
        raise PatchError(f"duplicate repair markers: {marker_count}")
    if stock_count != 1:
        raise PatchError(f"expected one stock updater function, found {stock_count}")
    if text.count(STOCK_CALLS) != 1 or text.count(STOCK_DSTAR_CALLS) != 1:
        raise PatchError("stock database call anchors are missing or ambiguous")

    before, old_function, after = section(text, STOCK_FUNCTION_START, DATABASE_FUNCTION_START)
    if old_function.count("http://www.pistar.uk/downloads/$2") != 1:
        raise PatchError("unsupported stock downloadAndValidate function")

    patched = before + SAFE_UPDATER + after
    patched = patched.replace(STOCK_CALLS, REPAIRED_CALLS, 1)
    patched = patched.replace(STOCK_DSTAR_CALLS, REPAIRED_DSTAR_CALLS, 1)
    return patched


def patch_file(path: Path) -> None:
    original = path.read_text(encoding="utf-8")
    patched = patch_text(original)
    if patched != original:
        path.write_text(patched, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Repair the DVSwitch TXT database updater")
    parser.add_argument("--dvswitch", required=True, type=Path)
    args = parser.parse_args()
    patch_file(args.dvswitch)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
