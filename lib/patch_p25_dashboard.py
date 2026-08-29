#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

"""Repair P25 remote-command link detection in a temporary functions.php copy."""

from __future__ import annotations

import argparse
from pathlib import Path


class PatchError(RuntimeError):
    pass


P25_LOG_START = "function getP25GatewayLog() {"
NXDN_LOG_START = "function getNXDNGatewayLog() {"
P25_CASE_START = '    case "P25":'
P25_CASE_END = "function getActualReflector("
STOCK_FILTER = '"Link|Starting|Unlink|unlinking"'
V1_FILTER = '"Link|Starting|Unlink|unlinking|Switched"'
V2_FILTER = '"Link|Starting|Unlink|unlinking|Switched|Statically linked"'
V1_PARSER_MARKER = 'preg_match("/Switched to reflector ([0-9]+)/", $logLine, $matches)'
V2_PARSER_MARKER = 'preg_match("/(?:Switched|Statically linked) to reflector ([0-9]+)/", $logLine, $matches)'
PARSER_ANCHOR = '               if (strpos($logLine,"Linked to")) {'
V1_PARSER = r'''               if (preg_match("/Switched to reflector ([0-9]+)/", $logLine, $matches)) {
                  return "Linked to <span style=\"color:#b5651d;font-weight:bold;\">TG ".$matches[1]."</span>";
               }
'''
V2_PARSER = r'''               if (preg_match("/(?:Switched|Statically linked) to reflector ([0-9]+)/", $logLine, $matches)) {
                  return "Linked to <span style=\"color:#b5651d;font-weight:bold;\">TG ".$matches[1]."</span>";
               }
'''


def split_once(text: str, start: str, end: str, description: str) -> tuple[str, str, str]:
    if text.count(start) != 1 or text.count(end) != 1:
        raise PatchError(f"expected one {description} start and end anchor")
    before, remainder = text.split(start, 1)
    middle, after = remainder.split(end, 1)
    return before, middle, after


def patch_text(text: str) -> str:
    before_log, p25_log, after_log = split_once(
        text, P25_LOG_START, NXDN_LOG_START, "P25 log reader"
    )
    before_case, p25_case, after_case = split_once(
        after_log, P25_CASE_START, P25_CASE_END, "P25 parser"
    )

    stock_filters = p25_log.count(STOCK_FILTER)
    v1_filters = p25_log.count(V1_FILTER)
    v2_filters = p25_log.count(V2_FILTER)
    v1_parsers = p25_case.count(V1_PARSER_MARKER)
    v2_parsers = p25_case.count(V2_PARSER_MARKER)
    anchor_count = p25_case.count(PARSER_ANCHOR)

    if (stock_filters, v1_filters, v2_filters, v1_parsers, v2_parsers, anchor_count) == (2, 0, 0, 0, 0, 1):
        p25_log = p25_log.replace(STOCK_FILTER, V2_FILTER)
        p25_case = p25_case.replace(PARSER_ANCHOR, V2_PARSER + PARSER_ANCHOR, 1)
    elif (stock_filters, v1_filters, v2_filters, v1_parsers, v2_parsers, anchor_count) == (0, 2, 0, 1, 0, 1):
        p25_log = p25_log.replace(V1_FILTER, V2_FILTER)
        p25_case = p25_case.replace(V1_PARSER, V2_PARSER, 1)
    elif (stock_filters, v1_filters, v2_filters, v1_parsers, v2_parsers, anchor_count) == (0, 0, 2, 0, 1, 1):
        pass
    else:
        raise PatchError(
            "unsupported, mixed, or ambiguous P25 dashboard state "
            f"(stock_filters={stock_filters}, v1_filters={v1_filters}, "
            f"v2_filters={v2_filters}, v1_parsers={v1_parsers}, "
            f"v2_parsers={v2_parsers}, linked_anchors={anchor_count})"
        )

    return (
        before_log
        + P25_LOG_START
        + p25_log
        + NXDN_LOG_START
        + before_case
        + P25_CASE_START
        + p25_case
        + P25_CASE_END
        + after_case
    )


def patch_file(path: Path) -> None:
    original = path.read_text(encoding="utf-8")
    repaired = patch_text(original)
    if repaired != original:
        path.write_text(repaired, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Repair a temporary functions.php copy")
    parser.add_argument("--functions", required=True, type=Path)
    args = parser.parse_args()
    if not args.functions.is_file() or args.functions.is_symlink():
        parser.error("--functions must be a regular, non-symlink file")
    try:
        patch_file(args.functions)
    except PatchError as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
