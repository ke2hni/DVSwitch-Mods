#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Standalone P25/NXDN friendly-name patcher."""

from __future__ import annotations

import os
from pathlib import Path

MARKER = "// DVSwitch-Mods: P25/NXDN friendly-name display v1"
INCLUDE = "include_once dirname(dirname(__FILE__)).'/include/functions.php';"
FUNCTION_ANCHOR = "function getActualReflector("
P25_PLAIN = 'getActualLink($logLinesP25Gateway, "P25")'
NXDN_PLAIN = 'getActualLink($logLinesNXDNGateway, "NXDN")'
P25_WRAPPED = 'formatReflectorLink(getActualLink($logLinesP25Gateway, "P25"), "P25")'
NXDN_WRAPPED = 'formatReflectorLink(getActualLink($logLinesNXDNGateway, "NXDN"), "NXDN")'

PHP_FUNCTION = r'''// DVSwitch-Mods: P25/NXDN friendly-name display v1
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

class PatchError(RuntimeError):
    pass

def once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise PatchError(f"unsupported or ambiguous {label}: {count} matches")
    return text.replace(old, new, 1)

def patch_text(functions: str, status: str) -> tuple[str, str]:
    fm = functions.count(MARKER)
    wrappers = status.count("formatReflectorLink(")
    if fm == 0 and wrappers == 0:
        functions = once(functions, FUNCTION_ANCHOR, PHP_FUNCTION + FUNCTION_ANCHOR, "functions insertion anchor")
        status = once(status, P25_PLAIN, P25_WRAPPED, "P25 status call")
        status = once(status, NXDN_PLAIN, NXDN_WRAPPED, "NXDN status call")
    elif fm == 1 and wrappers == 2:
        if functions.count(PHP_FUNCTION) != 1 or status.count(P25_WRAPPED) != 1 or status.count(NXDN_WRAPPED) != 1:
            raise PatchError("incomplete P25/NXDN modification")
    elif fm or wrappers:
        raise PatchError("partial or ambiguous P25/NXDN modification")
    else:
        raise PatchError("unsupported P25/NXDN anchors")
    return functions, status

def main() -> None:
    functions_path = Path(os.environ["FUNCTIONS_CANDIDATE"])
    status_path = Path(os.environ["STATUS_CANDIDATE"])
    functions, status = patch_text(functions_path.read_text(), status_path.read_text())
    functions_path.write_text(functions)
    status_path.write_text(status)

if __name__ == "__main__":
    try:
        main()
    except PatchError as exc:
        raise SystemExit(f"ERROR: {exc}")
