#!/usr/bin/env python3

import importlib.util
import shutil
import subprocess
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


functions_fixture = '''<?php
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
    case "P25":
        foreach ($logLines as $logLine) {
               if (strpos($logLine,"Linked to")) {
                  return "Linked";
               }
        }
        break;
    }
}
function getActualReflector($logLines, $mode) { return $mode; }
'''

status_fixture = '''<?php
echo getActualLink($logLinesP25Gateway, "P25");
echo getActualLink($logLinesNXDNGateway, "NXDN");
'''

specialized_dvswitch_fixture = '''#!/bin/bash
function downloadAndValidateNXDN() { :; }
function downloadAndValidateP25() { :; }
function downloadDatabases() {
        downloadAndValidateNXDN
        downloadAndValidateP25
}
'''

stock_dvswitch_fixture = '''#!/bin/bash
function downloadAndValidate() { :; }
function downloadDatabases() {
        downloadAndValidate "NXDNHosts.txt" "NXDN_Hosts.txt" "dvswitch.org"
        downloadAndValidate "P25Hosts.txt" "P25_Hosts.txt" "dvswitch.org"
}
'''

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    functions = root / "functions.php"
    status = root / "status.php"
    updater = root / "dvswitch.sh"
    functions.write_text(functions_fixture, encoding="utf-8")
    status.write_text(status_fixture, encoding="utf-8")
    updater.write_text(specialized_dvswitch_fixture, encoding="utf-8")

    module.patch_file(functions, "functions")
    module.patch_file(status, "status")
    module.patch_file(updater, "dvswitch")
    first_functions = functions.read_text(encoding="utf-8")
    first_status = status.read_text(encoding="utf-8")
    first_updater = updater.read_text(encoding="utf-8")

    require(first_functions.count("function formatReflectorLink(") == 1, "friendly-name function missing")
    require(first_functions.count("Switched to reflector ([0-9]+)") == 1, "P25 remote-command parser missing")
    require(first_functions.count('"Link|Starting|Unlink|unlinking|Switched"') == 2, "P25 Switched log filters missing")
    nxdn_log = first_functions.split("function getNXDNGatewayLog() {", 1)[1].split("function getActualLink", 1)[0]
    require(nxdn_log.count('"Link|Starting|Unlink|unlinking"') == 2, "NXDN filters changed unexpectedly")
    require("htmlspecialchars" in first_functions, "UTF-8-safe escaping missing")
    require('array("name", "sponsor")' in first_functions, "lookup order missing")
    require(first_status.count("formatReflectorLink(") == 2, "status wrappers missing")
    require(first_updater.count("function downloadAndValidateReflectorJSON()") == 1, "JSON updater missing")
    require(first_updater.count('downloadAndValidateReflectorJSON "NXDN"') == 1, "NXDN call missing")
    require(first_updater.count('downloadAndValidateReflectorJSON "P25"') == 1, "P25 call missing")
    if shutil.which("php"):
        subprocess.run(["php", "-l", str(functions)], check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["php", "-l", str(status)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["bash", "-n", str(updater)], check=True)

    module.patch_file(functions, "functions"); module.patch_file(status, "status"); module.patch_file(updater, "dvswitch")
    require(functions.read_text(encoding="utf-8") == first_functions, "functions patch is not idempotent")
    require(status.read_text(encoding="utf-8") == first_status, "status patch is not idempotent")
    require(updater.read_text(encoding="utf-8") == first_updater, "updater patch is not idempotent")

    stock = root / "stock-dvswitch.sh"
    stock.write_text(stock_dvswitch_fixture, encoding="utf-8")
    module.patch_file(stock, "dvswitch")
    first_stock = stock.read_text(encoding="utf-8")
    require(first_stock.count('downloadAndValidateReflectorJSON "NXDN"') == 1, "stock NXDN call missing")
    require(first_stock.count('downloadAndValidateReflectorJSON "P25"') == 1, "stock P25 call missing")
    module.patch_file(stock, "dvswitch")
    require(stock.read_text(encoding="utf-8") == first_stock, "stock patch is not idempotent")

for function in (
    lambda: module.patch_functions("<?php\n"),
    lambda: module.patch_dvswitch("#!/bin/bash\nfunction downloadDatabases() {\n}\n"),
):
    try:
        function()
    except module.PatchError:
        pass
    else:
        raise AssertionError("missing anchor was accepted")

print("P25/NXDN patcher tests passed.")
