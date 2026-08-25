#!/usr/bin/env python3

# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

"""Apply the independently written P25/NXDN additions to temporary copies."""

from __future__ import annotations

import argparse
from pathlib import Path


class PatchError(RuntimeError):
    pass


PHP_FUNCTION = r'''// DVSwitch dashboard friendly P25/NXDN reflector names.
function formatReflectorLink($linkText, $mode) {
        if ($mode !== "P25" && $mode !== "NXDN") { return $linkText; }
        if (!preg_match('/(?:TG|reflector)\s*([0-9]+)/i', strip_tags($linkText), $matches)) { return $linkText; }
        $number = $matches[1];
        $jsonFile = "/var/lib/mmdvm/".$mode."Hosts.json";
        $label = "";
        if (is_readable($jsonFile)) {
                $json = json_decode(file_get_contents($jsonFile), true);
                if (isset($json["reflectors"]) && is_array($json["reflectors"])) {
                        foreach ($json["reflectors"] as $reflector) {
                                if (!isset($reflector["designator"]) || (string)$reflector["designator"] !== $number) { continue; }
                                foreach (array("name", "sponsor") as $field) {
                                        if (!isset($reflector[$field]) || !is_string($reflector[$field])) { continue; }
                                        $candidate = trim(preg_replace('/\s+/u', ' ', str_replace('_', ' ', $reflector[$field])));
                                        if ($candidate !== "" && preg_match('/^[0-9]+$/', $candidate) !== 1) { $label = $candidate; break; }
                                }
                                break;
                        }
                }
        }
        if ($label === "") { $label = "TG ".$number; }
        $label = htmlspecialchars($label, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8");
        return "Reflector<br/><span style=\"color:#b5651d;font-weight:bold;display:inline-block;max-width:100%;white-space:normal;word-break:normal;overflow-wrap:break-word;text-align:center;\">".$label."</span>";
}

'''

SHELL_FUNCTION = r'''#################################################################
# Download and validate a RefCheck reflector JSON database.
# A failed update preserves the last known-good JSON file.
#################################################################
function downloadAndValidateReflectorJSON() {
    declare _mode="$1" _name _url _live _tmp _recordCount _fileSize
    case "${_mode}" in
        P25|NXDN) _name="${_mode}Hosts.json" ;;
        *) echo "Error, unsupported reflector JSON mode ${_mode}"; _ERRORCODE=$ERROR_INVALID_ARGUMENT; return ;;
    esac
    _url="https://hostfiles.refcheck.radio/${_name}"
    _live="${MMDVM_DIR}/${_name}"
    _tmp="${_live}.tmp.$$"
    rm -f "${_tmp}"
    if ! ${DEBUG} curl --fail --location --silent --show-error --user-agent "DVSwitch" \
        --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 2 -o "${_tmp}" "${_url}"; then
        echo "Warning, ${_name} download failure; keeping existing ${_name}"
        rm -f "${_tmp}"; _ERRORCODE=$ERROR_FILE_NOT_FOUND; return
    fi
    if ! _recordCount=$(REFLECTOR_JSON="${_tmp}" python3 <<'PYJSON'
import json, os, sys
try:
    with open(os.environ["REFLECTOR_JSON"], "r", encoding="utf-8") as src:
        data = json.load(src)
    reflectors = data.get("reflectors")
    if not isinstance(reflectors, list) or len(reflectors) < 200:
        raise ValueError("missing or undersized reflectors array")
    for item in reflectors:
        if not isinstance(item, dict): raise ValueError("reflector record is not an object")
        if not isinstance(item.get("designator"), int) or not 0 < item["designator"] <= 65535: raise ValueError("invalid reflector designator")
        if not isinstance(item.get("port"), int) or not 0 < item["port"] <= 65535: raise ValueError("invalid reflector port")
        if item.get("name") is not None and not isinstance(item["name"], str): raise ValueError("invalid reflector name")
        if item.get("sponsor") is not None and not isinstance(item["sponsor"], str): raise ValueError("invalid reflector sponsor")
    if not any(item["designator"] == 10200 for item in reflectors): raise ValueError("known reflector 10200 is missing")
    print(len(reflectors))
except Exception as exc:
    sys.stderr.write("Reflector JSON validation failed: %s\n" % exc); sys.exit(1)
PYJSON
    ); then
        echo "Error, downloaded ${_name} is invalid; keeping existing ${_name}"
        rm -f "${_tmp}"; _ERRORCODE=$ERROR_INVALID_FILE; return
    fi
    _fileSize=$(wc -c < "${_tmp}")
    chown root:root "${_tmp}"; chmod 0644 "${_tmp}"
    if ! mv -f "${_tmp}" "${_live}"; then
        echo "Error, unable to install validated ${_name}"; rm -f "${_tmp}"; _ERRORCODE=$ERROR_INVALID_FILE; return
    fi
    echo "${_name} downloaded from RefCheck and validated successfully (${_recordCount} reflectors, ${_fileSize} bytes)"
}

'''


def insert_once(text: str, marker: str, addition: str, description: str) -> str:
    count = text.count(marker)
    if count != 1:
        raise PatchError(f"expected one {description} marker, found {count}")
    return text.replace(marker, addition + marker, 1)


def replace_once(text: str, old: str, new: str, description: str) -> str:
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise PatchError(f"expected one {description}, found {count}")
    return text.replace(old, new, 1)


def patch_functions(text: str) -> str:
    if text.count("function formatReflectorLink(") == 1:
        return text
    if "function formatReflectorLink(" in text:
        raise PatchError("duplicate formatReflectorLink function")
    return insert_once(text, "function getActualReflector(", PHP_FUNCTION, "getActualReflector")


def patch_status(text: str) -> str:
    text = replace_once(
        text,
        'getActualLink($logLinesP25Gateway, "P25")',
        'formatReflectorLink(getActualLink($logLinesP25Gateway, "P25"), "P25")',
        "P25 status call",
    )
    return replace_once(
        text,
        'getActualLink($logLinesNXDNGateway, "NXDN")',
        'formatReflectorLink(getActualLink($logLinesNXDNGateway, "NXDN"), "NXDN")',
        "NXDN status call",
    )


def patch_dvswitch(text: str) -> str:
    if text.count("function downloadAndValidateReflectorJSON()") == 0:
        text = insert_once(text, "function downloadDatabases() {", SHELL_FUNCTION, "downloadDatabases")
    elif text.count("function downloadAndValidateReflectorJSON()") != 1:
        raise PatchError("duplicate reflector JSON updater function")
    text = replace_once(
        text,
        '        downloadAndValidateNXDN\n',
        '        downloadAndValidateNXDN\n        downloadAndValidateReflectorJSON "NXDN"\n',
        "NXDN database updater call",
    )
    return replace_once(
        text,
        '        downloadAndValidateP25\n',
        '        downloadAndValidateP25\n        downloadAndValidateReflectorJSON "P25"\n',
        "P25 database updater call",
    )


def patch_file(path: Path, kind: str) -> None:
    original = path.read_text(encoding="utf-8")
    patchers = {"functions": patch_functions, "status": patch_status, "dvswitch": patch_dvswitch}
    patched = patchers[kind](original)
    path.write_text(patched, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Patch temporary DVSwitch Dashboard copies")
    parser.add_argument("--functions", type=Path)
    parser.add_argument("--status", type=Path)
    parser.add_argument("--dvswitch", type=Path)
    args = parser.parse_args()
    if not args.functions or not args.status or not args.dvswitch:
        parser.error("--functions, --status and --dvswitch are required")
    patch_file(args.functions, "functions")
    patch_file(args.status, "status")
    patch_file(args.dvswitch, "dvswitch")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
