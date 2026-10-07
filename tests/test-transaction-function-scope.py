#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Regression test: transaction rollback remains visible to EXIT traps."""

from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = ROOT / "lib/transaction.sh"

with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    target = base / "managed-file"
    target.write_text("original\n")
    command = r'''
set -Eeuo pipefail
TARGET=$1
BACKUPS=$2
LIBRARY=$3
rollback() { status=$?; dvsm_transaction_rollback; exit "$status"; }
trap rollback EXIT
install_component() {
    . "$LIBRARY"
    dvsm_transaction_begin "$BACKUPS" >/dev/null
    dvsm_backup_file "$TARGET" >/dev/null
    printf 'partial\n' > "$TARGET"
    false
}
install_component
'''
    result = subprocess.run(
        ["bash", "--noprofile", "--norc", "-c", command, "test-transaction", str(target), str(base / "backups"), str(LIBRARY)],
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0, "simulated component failure unexpectedly succeeded"
    assert target.read_text() == "original\n", "EXIT trap could not access transaction arrays to roll back"

installer = (ROOT / "mod-dashboard-activity-modes.sh").read_text()
assert "systemctl reset-failed dvswitch-mods-activity-mode-history.path dvswitch-mods-activity-mode-history.service >/dev/null 2>&1 || true" in installer
print("PASS: transaction rollback survives function return; missing systemd failed-state is nonfatal")
