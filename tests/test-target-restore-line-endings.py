#!/usr/bin/env python3
"""Verify Target restore tolerates only newline-style differences."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import re
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("FAIL: " + message)


def function_source(name: str) -> str:
    source = (ROOT / "mod-dashboard-targets.sh").read_text(encoding="utf-8")
    match = re.search(rf"(?ms)^{re.escape(name)}\(\)\s*\{{.*?^}}", source)
    require(match is not None, f"missing {name}()")
    return match.group(0)


spec = importlib.util.spec_from_file_location("target_patcher", ROOT / "lib/patch_dashboard_targets.py")
patcher = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(patcher)

with tempfile.TemporaryDirectory(prefix="dvsm-target-newlines-") as temporary:
    root = Path(temporary)
    backups = root / "install-20261009-205154"
    backups.mkdir()
    live_lh = root / "live-lh.php"
    live_local = root / "live-localtx.php"
    backup_lh = backups / "0001-lh.php"
    backup_local = backups / "0002-localtx.php"
    manifest = backups / "MANIFEST"

    old_lh, _ = patcher.block("lh.php")
    old_local, _ = patcher.block("localtx.php")
    lh_stock = (
        "<?php\ninclude_once dirname(dirname(__FILE__)).'/include/functions.php';    \n"
        + old_lh
    )
    local_stock = (
        "<?php\ninclude_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_fcc_first_names.php';\n"
        + old_local + "</div>\n<br>\n"
    )
    backup_lh.write_bytes(lh_stock.encode())
    backup_local.write_bytes(local_stock.encode())
    manifest.write_text(
        f"1\t{live_lh}\t{backup_lh}\n1\t{live_local}\t{backup_local}\n",
        encoding="utf-8",
    )

    expected_lh = patcher.patch_text(lh_stock, "lh.php")
    expected_local = patcher.patch_text(local_stock, "localtx.php")
    live_lh.write_bytes(expected_lh.replace("\n", "\r\n").encode())
    live_local.write_bytes(expected_local.replace("\n", "\r\n").encode())

    harness = root / "validate.sh"
    harness.write_text(
        'set -euo pipefail\n'
        'die() { printf "ERROR: %s\\n" "$*" >&2; exit 1; }\n'
        f'LH_TARGET={shlex.quote(str(live_lh))}\n'
        f'LOCALTX_TARGET={shlex.quote(str(live_local))}\n'
        f'HELPER_TARGET={shlex.quote(str(root / "helper.php"))}\n'
        f'PATCHER={shlex.quote(str(ROOT / "lib/patch_dashboard_targets.py"))}\n'
        + function_source("same_content_ignoring_line_endings") + "\n"
        + function_source("validate_target_restore_state") + "\n"
        + f'validate_target_restore_state {shlex.quote(str(backups))}\n',
        encoding="utf-8",
    )
    accepted = subprocess.run(["bash", str(harness)], text=True, capture_output=True)
    require(accepted.returncode == 0,
            "Target restore rejected CRLF-only differences: " + accepted.stdout + accepted.stderr)
    require("differs from the verified Target state only in line endings" in accepted.stdout,
            "Target restore did not report the safe line-ending normalization")

    live_lh.write_bytes(live_lh.read_bytes() + b"// unrelated change\r\n")
    refused = subprocess.run(["bash", str(harness)], text=True, capture_output=True)
    require(refused.returncode != 0 and "changes beyond this mod's patch" in refused.stderr,
            "Target restore accepted content changes along with newline differences")

print("PASS: Target restore accepts LF/CRLF-only differences and rejects content drift")
