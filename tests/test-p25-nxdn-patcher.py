#!/usr/bin/env python3

import importlib.util
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "lib" / "patch_p25_nxdn.py"
spec = importlib.util.spec_from_file_location("patch_p25_nxdn", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


functions_fixture = """<?php
function existingDashboardFunction() { return true; }
function getActualReflector($logLines, $mode) { return $mode; }
"""

status_fixture = """<?php
echo getActualLink($logLinesP25Gateway, \"P25\");
echo getActualLink($logLinesNXDNGateway, \"NXDN\");
"""

with tempfile.TemporaryDirectory() as directory:
    directory_path = Path(directory)
    functions_path = directory_path / "dashboard-functions.txt"
    status_path = directory_path / "dashboard-status.txt"
    functions_path.write_text(functions_fixture, encoding="utf-8")
    status_path.write_text(status_fixture, encoding="utf-8")

    module.patch_file(functions_path, "functions")
    module.patch_file(status_path, "status")
    first_functions = functions_path.read_text(encoding="utf-8")
    first_status = status_path.read_text(encoding="utf-8")

    require(first_functions.count("function formatReflectorLink(") == 1, "friendly-name function missing or duplicated")
    require("htmlspecialchars" in first_functions, "UTF-8-safe escaping missing")
    require('array("name", "sponsor")' in first_functions, "name-to-sponsor lookup order missing")
    require(first_status.count("formatReflectorLink(") == 2, "status wrappers missing")

    module.patch_file(functions_path, "functions")
    module.patch_file(status_path, "status")
    require(functions_path.read_text(encoding="utf-8") == first_functions, "functions patch is not idempotent")
    require(status_path.read_text(encoding="utf-8") == first_status, "status patch is not idempotent")

try:
    module.patch_functions("<?php\n")
except module.PatchError:
    pass
else:
    raise AssertionError("missing anchor was accepted")

print("P25/NXDN patcher tests passed.")
