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


def patch_file(path: Path, kind: str) -> None:
    original = path.read_text(encoding="utf-8")
    patched = patch_functions(original) if kind == "functions" else patch_status(original)
    path.write_text(patched, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Patch temporary DVSwitch Dashboard copies")
    parser.add_argument("--functions", type=Path)
    parser.add_argument("--status", type=Path)
    args = parser.parse_args()
    if not args.functions or not args.status:
        parser.error("--functions and --status are required")
    patch_file(args.functions, "functions")
    patch_file(args.status, "status")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
