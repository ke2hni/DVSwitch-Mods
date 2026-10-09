#!/usr/bin/env python3
# Version: 1.0.0
# SPDX-License-Identifier: MIT

"""Ensure --check all reports child failures and continues checking."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
MANAGER = ROOT / "manage-dvswitch-mods.sh"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("FAIL: " + message)


source = MANAGER.read_text(encoding="utf-8")
start = source.index("check_all() {")
end = source.index("\n}\n\nlast_state_line()", start) + 2
check_all = source[start:end]
main = source[source.index("main() {"):]
install_requested = source[source.index("install_requested() {"):source.index("\nuninstall_requested() {")]

require('if output=$("$CHILD_SCRIPT" --check 2>&1); then' in check_all,
        "check_all must capture a failed child check without firing the ERR trap")
require("if check_requested \"$2\"; then" in main,
        "main must return an expected nonzero check result without the unexpected-failure trap")
require("ensure_build_dependencies\n    preflight_recorded_backups" in install_requested,
        "installation must verify build dependencies before component checks")
require('apt-get update && sudo apt-get install -y build-essential' in source,
        "manager must show the explicit install command when dependencies are missing")
require('apt-get update && apt-get install -y build-essential' not in source,
        "manager must not install packages without explicit user action")

with tempfile.TemporaryDirectory(prefix="dvsm-manager-check-") as temporary:
    root = Path(temporary)
    fake_bin = root / "bin"
    fake_bin.mkdir()
    (root / "missing-tool").write_text(
        "#!/bin/sh\nprintf 'FAIL: Required command not found: make\\n'\nexit 1\n",
        encoding="utf-8",
    )
    (root / "ready-tool").write_text(
        "#!/bin/sh\nprintf 'REPAIR READY: second component was checked\\n'\n",
        encoding="utf-8",
    )
    for name in ("missing-tool", "ready-tool"):
        (root / name).chmod(0o755)

    stubs = f'''\
set -Eeuo pipefail
trap 'printf '"'"'UNEXPECTED ERR TRAP\\n'"'"' >&2; exit 99' ERR
COMPONENTS=(first second)
COMPONENT=""
CHILD_SCRIPT=""
MANAGER_PHASE="checking all components"
require_command() {{ :; }}
should_skip_all_component() {{ return 1; }}
select_component() {{ COMPONENT=$1; CHILD_SCRIPT={str(root)!r}/"$([[ $1 == first ]] && printf missing-tool || printf ready-tool)"; BACKUP_ROOT={str(root)!r}; }}
dependency_hint() {{ printf 'missing a required command'; }}
print_named_list() {{ printf '%s\\n' "$1"; shift; if [[ $# -eq 0 ]]; then printf '  - None\\n'; else printf '  - %s\\n' "$@"; fi; }}
{check_all}
if check_all; then result=0; else result=$?; fi
printf 'HARNESS_STATUS=%s\\n' "$result"
exit 0
'''
    result = subprocess.run(
        ["bash", "-c", stubs],
        env={**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}"},
        text=True,
        capture_output=True,
        check=False,
    )
    output = result.stdout + result.stderr
    require(result.returncode == 0, "check_all harness failed: " + output)
    require("FAIL: Required command not found: make" in output,
            "failed child's diagnostic was lost")
    require("REPAIR READY: second component was checked" in output,
            "check_all stopped before checking the later component")
    require("Failed or blocked:" in output and "first — missing a required command" in output,
            "failed component was not included in the summary")
    require("second" in output and "HARNESS_STATUS=1" in output,
            "check_all did not report its aggregate failure status")
    require("UNEXPECTED ERR TRAP" not in output,
            "expected failed check incorrectly invoked the manager ERR trap")

print("PASS: --check all captures component failures, continues, and summarizes them")
