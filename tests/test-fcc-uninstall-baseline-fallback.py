#!/usr/bin/env python3
"""Verify FCC uninstall can recover a verified baseline after a no-op upgrade backup."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("FAIL: " + message)


def extract_function(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^{re.escape(name)}\(\) \{{.*?^\}}", source)
    require(match is not None, f"missing {name}()")
    return match.group(0)


spec = importlib.util.spec_from_file_location("fcc_patcher", ROOT / "lib/patch_dashboard_first_names.py")
patcher = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(patcher)

fixture = '''<?php
include_once dirname(dirname(__FILE__)).'/include/functions.php';    
      <th>Time (<?php echo date('T')?>)</th>
      <th>Callsign</th>
<?php
    if (DISPLAYNAME == "YES" && file_exists(DMRIDDATPATH."/DMRIds.dat") && ! empty(DMRIDDATPATH."/DMRIds.dat")) { echo "<th>Name</th>"; }
?>
        if ((is_numeric($listElem[2]) || strpos($listElem[2], "openSPOT") !== FALSE) && (strlen($listElem[2])==7)) {
// Display NAME by DV8AWC
        if ( DISPLAYNAME == "YES" ) {
        }
        if (strlen($listElem[4]) == 1) { $listElem[4] = str_pad($listElem[4], 8, " ", STR_PAD_LEFT); }
'''

installer = (ROOT / "mod-dashboard-fcc-first-names.sh").read_text(encoding="utf-8")
functions = "\n".join(extract_function(installer, name) for name in
                     ("manifest_target_row", "resolve_uninstall_backup"))

with tempfile.TemporaryDirectory(prefix=".fcc-uninstall-fallback-", dir=ROOT) as temporary:
    root = Path(temporary)
    backups = root / "backups"
    work = root / "work"
    backups.mkdir()
    work.mkdir()
    baseline = root / "stock-lh.php"
    baseline.write_text(fixture, encoding="utf-8")
    live = root / "current" / "lh.php"
    live.parent.mkdir()
    live.write_text(patcher.patch_text(fixture), encoding="utf-8")

    initial = backups / "install-20261008-222613"
    active = backups / "install-20261009-001542"
    initial.mkdir()
    active.mkdir()
    saved_lh = initial / "0007-lh.php"
    saved_lh.write_text(fixture, encoding="utf-8")
    (initial / "MANIFEST").write_text(f"1\t{live}\t{saved_lh}\n", encoding="utf-8")
    (active / "MANIFEST").write_text("1\t/usr/local/lib/old-helper.php\t/old-helper.php\n", encoding="utf-8")

    harness = root / "resolve.sh"
    harness.write_text(
        'set -Eeuo pipefail\nset -x\n'
        'die() { printf "ERROR: %s\\n" "$1" >&2; exit 1; }\n'
        'require_file() { [[ -f "$1" && ! -L "$1" ]] || die "missing backup file: $1"; }\n'
        f'BACKUP_ROOT={str(backups)!r}\nWORK_ROOT={str(work)!r}\nWORK_DIR=""\n'
        f'LH_TARGET={str(live)!r}\nPATCHER={str(ROOT / "lib/patch_dashboard_first_names.py")!r}\n'
        'UNINSTALL_DIRECTORY=""\nUNINSTALL_ORIGINAL_LH=""\n'
        + functions + '\n'
        'resolve_uninstall_backup install-20261009-001542\n'
        'printf "SELECTED=%s\\nORIGINAL=%s\\n" "$UNINSTALL_DIRECTORY" "$UNINSTALL_ORIGINAL_LH"\n',
        encoding="utf-8",
    )
    result = subprocess.run(["bash", str(harness)], text=True, capture_output=True)
    require(result.returncode == 0, "fallback did not select a protected baseline: " + result.stdout + result.stderr)
    require(f"SELECTED={initial}" in result.stdout, "fallback did not choose the earlier original install backup")
    require(f"ORIGINAL={saved_lh}" in result.stdout, "fallback selected the wrong lh.php snapshot")
    require("Verified earlier FCC baseline" in result.stdout, "fallback did not explain the verified selection")

    live.write_text(live.read_text(encoding="utf-8") + "// unrelated edit\n", encoding="utf-8")
    refused = subprocess.run(["bash", str(harness)], text=True, capture_output=True)
    require(refused.returncode != 0, "fallback accepted a current lh.php with unrelated edits")
    require("no earlier protected baseline matches" in refused.stderr,
            "unsafe fallback refusal did not explain why it stopped")
    require(live.read_text(encoding="utf-8").endswith("// unrelated edit\n"),
            "refused fallback changed the current dashboard file")

print("PASS: FCC uninstall selects only a matching earlier pre-FCC backup and refuses dashboard drift")
