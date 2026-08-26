#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

"""Unit tests for the standalone DVSwitch TXT updater patcher."""

from __future__ import annotations

import importlib.util
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PATCHER = ROOT / "lib" / "patch_dvswitch_txt_updater.py"

spec = importlib.util.spec_from_file_location("patch_dvswitch_txt_updater", PATCHER)
if spec is None or spec.loader is None:
    raise RuntimeError("unable to load TXT updater patcher")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


STOCK_FIXTURE = r'''#!/bin/bash
SCRIPT_VERSION="1.6.2"
MMDVM_DIR="/var/lib/mmdvm"
DEBUG=""
ERROR_FILE_NOT_FOUND=1
ERROR_INVALID_FILE=2
_ERRORCODE=0

function downloadAndValidate() {
    ${DEBUG} curl --fail -o "$MMDVM_DIR/$1" -s "http://www.pistar.uk/downloads/$2"
    if (( $? != 0 )); then
        echo "Warning, download failure"
        _ERRORCODE=$ERROR_FILE_NOT_FOUND
    fi
    if [ ! -f $MMDVM_DIR/$1 ]; then
        echo "Error, $1 file does not seem to exist"
        _ERRORCODE=$ERROR_INVALID_FILE
    else
        declare _fileSize=`wc -c $MMDVM_DIR/$1 | awk '{print $1}'`
        if (( ${_fileSize} < 10 )); then
            echo "Error, $1 file has no contents"
            _ERRORCODE=$ERROR_INVALID_FILE
        else
            declare isValid=`grep $3 "$MMDVM_DIR/$1"`
            if [ -z "$isValid" ]; then
                echo "Error, $1 file does not seem to be valid"
                _ERRORCODE=$ERROR_INVALID_FILE
            fi
        fi
    fi
}

#################################################################
# Download all user databases
#################################################################
function downloadDatabases() {
    if [ -d "${MMDVM_DIR}" ] && [ -d "${AB_DIR}" ]; then
        downloadAndValidate "NXDNHosts.txt" "NXDN_Hosts.txt" "dvswitch.org"
        downloadAndValidate "P25Hosts.txt" "P25_Hosts.txt" "dvswitch.org"
        downloadAndValidate "TGList_BM.txt" "TGList_BM.txt" "DVSWITCH"
        downloadAndValidate "YSFHosts.txt" "YSF_Hosts.txt" "dvswitch.org"

        downloadAndValidate "TGList_TGIF.txt" "TGList_TGIF.txt" "TGIF"
# TG list direct from BM
# TG list from TGIF
# TG list from FreeDMR

        downloadAndValidate "FCSRooms.txt" "FCS_Hosts.txt" "FCS00106"
        downloadAndValidate "DCS_Hosts.txt" "DCS_Hosts.txt" "DCS006"
        downloadAndValidate "DPlus_Hosts.txt" "DPlus_Hosts.txt" "REF030"
        downloadAndValidate "DExtra_Hosts.txt" "DExtra_Hosts.txt" "XRF012"
        downloadAndValidate "XLXHosts.txt" "XLXHosts.txt" "001;"
        downloadAndValidate "APRS_Hosts.txt" "APRS_Hosts.txt" "noam.aprs2.net"
    fi
}
'''


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def require_patch_error(text: str, description: str) -> None:
    try:
        module.patch_text(text)
    except module.PatchError:
        return
    raise AssertionError(f"unsafe input accepted: {description}")


with tempfile.TemporaryDirectory() as directory:
    target = Path(directory) / "dvswitch.sh"
    target.write_text(STOCK_FIXTURE, encoding="utf-8")

    module.patch_file(target)
    repaired = target.read_text(encoding="utf-8")

    require(repaired.count(module.MARKER) == 1, "repair marker missing or duplicated")
    require(repaired.count("function downloadAndValidateDatabase()") == 1, "safe downloader missing")
    require(repaired.count("function installValidatedDatabase()") == 1, "metadata-preserving installer missing")
    require('mktemp "${MMDVM_DIR}/.${_name}.download.XXXXXX"' in repaired, "same-directory mktemp missing")
    require('chown --reference="${_live}"' in repaired, "ownership preservation missing")
    require('chmod --reference="${_live}"' in repaired, "mode preservation missing")
    require('chown root:root "${_candidate}"' in repaired, "new-file ownership missing")
    require('chmod 0644 "${_candidate}"' in repaired, "new-file mode missing")
    require('mv -f -- "${_candidate}" "${_live}"' in repaired, "atomic replacement missing")
    require(
        'if [ "${_kind}" = GENERIC ]; then' in repaired,
        "generic success-output branch missing",
    )
    require(
        'echo "${_name} downloaded and validated successfully (${_fileSize} bytes)"' in repaired,
        "generic byte-only success output missing",
    )

    expected_calls = (
        'downloadAndValidateDatabase "NXDNHosts.txt" "https://hostfiles.refcheck.radio/NXDNHosts.txt" NXDN',
        'downloadAndValidateDatabase "P25Hosts.txt" "https://hostfiles.refcheck.radio/P25Hosts.txt" P25',
        'downloadAndValidateDatabase "TGList_BM.txt" "https://api.brandmeister.network/v2/talkgroup" BM',
        'downloadAndValidateDatabase "YSFHosts.txt" "https://hostfiles.refcheck.radio/YSFHosts.txt" YSF',
        'downloadAndValidateDatabase "TGList_TGIF.txt" "https://api.tgif.network/dmr/talkgroups/csv" TGIF',
        'downloadAndValidateDatabase "DCS_Hosts.txt" "https://www.pistar.uk/downloads/DCS_Hosts.txt" DCS',
        'downloadAndValidateDatabase "DPlus_Hosts.txt" "https://www.pistar.uk/downloads/DPlus_Hosts.txt" DPLUS',
        'downloadAndValidateDatabase "DExtra_Hosts.txt" "https://www.pistar.uk/downloads/DExtra_Hosts.txt" DEXTRA',
        'downloadAndValidateDatabase "XLXHosts.txt" "https://hostfiles.refcheck.radio/XLXHosts.txt" XLX',
    )
    for call in expected_calls:
        require(repaired.count(call) == 1, f"expected one repaired call: {call}")

    require(
        'downloadAndValidate "FCSRooms.txt" "FCS_Hosts.txt" "FCS00106"' in repaired,
        "FCS compatibility call changed unexpectedly",
    )
    require(
        'downloadAndValidate "APRS_Hosts.txt" "APRS_Hosts.txt" "noam.aprs2.net"' in repaired,
        "APRS compatibility call changed unexpectedly",
    )
    require("https://www.pistar.uk/downloads/$2" in repaired, "generic Pi-Star source missing")
    require("P25Hosts.json" not in repaired and "NXDNHosts.json" not in repaired, "JSON modification leaked into repair")
    require("functions.php" not in repaired and "status.php" not in repaired, "dashboard modification leaked into repair")
    require("formatReflectorLink" not in repaired, "friendly-name modification leaked into repair")
    require('SCRIPT_VERSION="1.6.2"' in repaired, "upstream version changed")

    subprocess.run(["bash", "-n", str(target)], check=True)

    first = target.read_bytes()
    module.patch_file(target)
    require(target.read_bytes() == first, "second patch run changed repaired output")

require_patch_error(STOCK_FIXTURE.replace("function downloadAndValidate() {", "function missing() {", 1), "missing stock function")
require_patch_error(STOCK_FIXTURE + STOCK_FIXTURE, "duplicate stock structure")
require_patch_error(STOCK_FIXTURE.replace(module.STOCK_CALLS, "", 1), "missing primary call block")
require_patch_error(STOCK_FIXTURE.replace(module.STOCK_DSTAR_CALLS, "", 1), "missing D-Star call block")

mixed = module.patch_text(STOCK_FIXTURE).replace(module.REPAIRED_CALLS, module.REPAIRED_CALLS + module.STOCK_CALLS, 1)
require_patch_error(mixed, "mixed repaired and stock calls")

partial = module.patch_text(STOCK_FIXTURE).replace(module.REPAIRED_DSTAR_CALLS, module.STOCK_DSTAR_CALLS, 1)
require_patch_error(partial, "partially repaired call set")

duplicate_marker = module.patch_text(STOCK_FIXTURE).replace(module.MARKER, module.MARKER + "\n" + module.MARKER, 1)
require_patch_error(duplicate_marker, "duplicate repair marker")

print("PASS: DVSwitch TXT updater patcher tests")
