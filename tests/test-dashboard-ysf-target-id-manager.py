#!/usr/bin/env python3
# Version: 1.0.0
# SPDX-License-Identifier: MIT
"""Verify manager registration and install/check/restore support."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANAGER = (ROOT / "manage-dvswitch-mods.sh").read_text()
SCRIPT = ROOT / "mod-dashboard-ysf-target-id.sh"
assert SCRIPT.is_file() and SCRIPT.stat().st_mode & 0o111
assert "dashboard-ysf-target-id" in MANAGER.split("readonly -a COMPONENTS=(", 1)[1].split(")", 1)[0]
assert 'dashboard-ysf-target-id) CHILD_SCRIPT="$SCRIPT_DIR/mod-dashboard-ysf-target-id.sh"; BACKUP_ROOT="/var/backups/dvswitch-mods/dashboard-ysf-target-id"' in MANAGER
script_text = SCRIPT.read_text()
assert "--check" in script_text and "--install" in script_text and "--restore" in script_text
print("PASS: YSF target-ID component is standalone and registered with the manager")
