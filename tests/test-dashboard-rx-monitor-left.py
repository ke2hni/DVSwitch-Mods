#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Exercise RX Monitor position install, idempotency, and surgical uninstall."""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "mod-dashboard-rx-monitor-left.sh"
ORIGINAL = b'''<?php include_once 'include/config.php'; ?>
<div style="margin-top:8px;">
<?php
if ( RXMONITOR == "YES" ) {
echo '<button class="button link" onclick="playAudioToggle(8080, this)"><b>&nbsp;&nbsp;&nbsp;<img src=images/speaker.png alt="" style="vertical-align:middle">&nbsp;&nbsp;RX Monitor&nbsp;&nbsp;&nbsp;</b></button>';}
?>
</div></center>
</div>
<?php
function getMMDVMConfigFileContent() {
}
    echo '<td width="200px" valign="top" class="hide" style="border:none;background-color:#fafafa;">';
    echo '<div class="nav">'."\\n";
?>
'''


def run(script: Path, target: Path, backups: Path, fake_bin: Path, *args: str) -> str:
    env = os.environ.copy()
    env.update(
        DVS_RX_MONITOR_TARGET=str(target),
        DVS_RX_MONITOR_BACKUP_ROOT=str(backups),
        PATH=f"{fake_bin}:{env['PATH']}",
    )
    result = subprocess.run([str(script), *args], env=env, text=True, capture_output=True)
    if result.returncode:
        raise AssertionError(f"{args} failed:\n{result.stdout}{result.stderr}")
    return result.stdout


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="dvs-rx-monitor-test-") as temporary:
        root = Path(temporary)
        target = root / "index.php"
        backups = root / "backups"
        fake_bin = root / "bin"
        fake_bin.mkdir()
        php = fake_bin / "php"
        php.write_text("#!/bin/sh\nexit 0\n")
        php.chmod(0o755)
        target.write_bytes(ORIGINAL)

        output = run(INSTALLER, target, backups, fake_bin, "--check")
        assert "READY:" in output
        assert target.read_bytes() == ORIGINAL
        assert not backups.exists()

        output = run(INSTALLER, target, backups, fake_bin, "--install")
        match = re.search(r"Backup: (.+)", output)
        assert match, output
        backup_name = Path(match.group(1)).name
        installed = target.read_bytes()
        assert b"<div style=\"margin-top:8px;\">" not in installed
        assert installed.count(b"playAudioToggle(8080, this)") == 1
        assert installed.index(b"// DVSwitch-Mods: RX Monitor left of status v1") < installed.index(b"echo '<div class=\"nav\">'")
        assert installed.index(b"echo '<td width=\"200px\"") < installed.index(b"// DVSwitch-Mods: RX Monitor left of status v1")

        before_backup_count = len(list(backups.glob("install-*")))
        output = run(INSTALLER, target, backups, fake_bin, "--install")
        assert "already positioned" in output
        assert len(list(backups.glob("install-*"))) == before_backup_count == 1

        run(INSTALLER, target, backups, fake_bin, "--uninstall", backup_name)
        assert target.read_bytes() == ORIGINAL

    print("PASS: RX Monitor move is positioned in the left column, idempotent, and safely reversible")


if __name__ == "__main__":
    main()
