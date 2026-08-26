#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

import importlib.util
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "lib" / "patch_p25_dashboard.py"
spec = importlib.util.spec_from_file_location("patch_p25_dashboard", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


FIXTURE = '''<?php
function getP25GatewayLog() {
        $today = `egrep -a -h "Link|Starting|Unlink|unlinking" $logPath1`;
        $yesterday = `egrep -a -h "Link|Starting|Unlink|unlinking" $logPath2`;
}
function getNXDNGatewayLog() {
        $today = `egrep -a -h "Link|Starting|Unlink|unlinking" $logPath1`;
        $yesterday = `egrep -a -h "Link|Starting|Unlink|unlinking" $logPath2`;
}
function getActualLink($logLines, $mode) {
    switch ($mode) {
    case "NXDN":
        foreach ($logLines as $logLine) {
               if (strpos($logLine,"Linked to")) { return "NXDN"; }
        }
        break;
    case "P25":
        foreach ($logLines as $logLine) {
               if (strpos($logLine,"Linked to")) { return "P25"; }
        }
          break;
          }
}
'''


repaired = module.patch_text(FIXTURE)
require(repaired.count(module.REPAIRED_FILTER) == 2, "two P25 Switched filters were not installed")
require(repaired.count(module.STOCK_FILTER) == 2, "NXDN filters were changed")
require(repaired.count(module.PARSER_MARKER) == 1, "P25 remote-command parser was not installed")
require('TG ".$matches[1]' in repaired, "stock-compatible P25 talkgroup output is missing")
require(module.patch_text(repaired) == repaired, "patcher is not idempotent")

with tempfile.TemporaryDirectory() as directory:
    target = Path(directory) / "functions.php"
    target.write_text(FIXTURE, encoding="utf-8")
    module.patch_file(target)
    require(target.read_text(encoding="utf-8") == repaired, "file patch differs from text patch")


def must_reject(text: str, description: str) -> None:
    try:
        module.patch_text(text)
    except module.PatchError:
        return
    raise AssertionError(f"accepted {description}")


must_reject("<?php\n", "missing anchors")
must_reject(FIXTURE.replace(module.STOCK_FILTER, module.REPAIRED_FILTER, 1), "mixed log filters")
fixture_before_p25_anchor, fixture_after_p25_anchor = FIXTURE.rsplit(module.PARSER_ANCHOR, 1)
must_reject(fixture_before_p25_anchor + module.PARSER + module.PARSER_ANCHOR + fixture_after_p25_anchor, "mixed parser state")
must_reject(fixture_before_p25_anchor + module.PARSER_ANCHOR + "\n" + module.PARSER_ANCHOR + fixture_after_p25_anchor, "duplicate P25 parser anchor")
must_reject(FIXTURE.replace(module.P25_LOG_START, module.P25_LOG_START + "\n" + module.P25_LOG_START, 1), "duplicate P25 log function")

print("P25 dashboard compatibility patcher tests passed.")
