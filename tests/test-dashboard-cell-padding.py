#!/usr/bin/env python3
# Version: 1.0.0
"""Regression tests for cell-padding upgrades after FCC Name updates."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "mod-dashboard-cell-padding.sh"

CSS = '''table th {
    font-family: "Lucidia Console",Monaco,monospace;
    text-shadow: 1px 1px #<?php echo $tableHeadDropShaddow; ?>;
    text-decoration: none;
    background: #<?php echo $backgroundBanners; ?>;
    border: 1px solid #c0c0c0;
    padding: 2px 4px;
}
table td {
    color: #000000;
    font-family: "Lucidia Console",Monaco,monospace;
    text-decoration: none;
    border: 1px solid #000000;
    overflow-x: hidden;
    padding: 2px 4px;
}
'''

LH_MODIFIED = '''echo"<td align=\\"left\\" style=\\"color:green; font-weight:bold;\\">$listElem[1]</td>";
echo "<td align=\\"left\\" style=\\"color:#464646;\\"><a href=\\"https://database.radioid.net/database/view?id=$listElem[2]\\" target=\\"_blank\\"><span style=\\"color:#464646;font-weight:bold;\\">$listElem[2]</span></a></td>";
echo "<td align=\\"left\\"><a href=\\"http://www.qrz.com/db/$listElem[2]\\" target=\\"_blank\\"><b>$listElem[2]</b></a><span style=\\"color:#464646;font-weight:bold;\\">/$listElem[3]</span></td>";
echo "<td align=\\"left\\"><a href=\\"http://www.qrz.com/db/$listElem[2]\\" target=\\"_blank\\"><b>$listElem[2]</b></a></td>";
echo "<td align=\\"left\\" style=\\"color:#464646;\\"><b>$listElem[2]</b></td>";
echo '<td align="left"><span style="display:block;color:#b5651d;font-weight:bold;white-space:normal;">'.htmlspecialchars($dvsModsTarget, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").'</span></td>';
'''

NAME_COUNTRY_OLD = 'echo \'<td align="left" style="font-weight:bold;color:#464646;white-space:normal;overflow-wrap:anywhere;word-break:normal;width:12ch;min-width:12ch;max-width:12ch;">&nbsp;<b>\'.$dvsModsNameHtml.\'</b></td>\';'
NAME_COUNTRY_NEW = 'echo \'<td align="left" style="font-weight:bold;color:#464646;white-space:normal;overflow-wrap:anywhere;word-break:normal;width:12ch;min-width:12ch;max-width:12ch;"><b>\'.$dvsModsNameHtml.\'</b></td>\';'
NAME_LEGACY_OLD = 'echo \'<td align="left" style="font-weight:bold;color:#464646;white-space:normal;overflow-wrap:anywhere;word-break:normal;width:12ch;min-width:12ch;max-width:12ch;">&nbsp;<b>\'.htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").\'</b></td>\';'


def run(action: str, css: Path, lh: Path, backup: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ | {
        "CSS_FILE": str(css),
        "LH_FILE": str(lh),
        "BACKUP_ROOT": str(backup),
    }
    return subprocess.run(["bash", str(INSTALLER), action], text=True, capture_output=True, env=env)


def exercise(name_cell: str) -> None:
    with tempfile.TemporaryDirectory() as directory:
        temp = Path(directory)
        css = temp / "css.php"
        lh = temp / "lh.php"
        backups = temp / "backups"
        css.write_text(CSS)
        lh.write_text(LH_MODIFIED + name_cell + "\n")

        check = run("--check", css, lh, backups)
        assert check.returncode == 0, check.stdout + check.stderr
        assert "READY:" in check.stdout, check.stdout

        install = run("--install", css, lh, backups)
        assert install.returncode == 0, install.stdout + install.stderr
        assert "installed atomically" in install.stdout, install.stdout
        assert name_cell.replace("&nbsp;", "") in lh.read_text()
        backup_files = list(backups.glob("install-*/lh.php"))
        assert len(backup_files) == 1, f"expected one LH backup, got {backup_files}"
        assert name_cell in backup_files[0].read_text(), "backup did not preserve original Name cell"

        final_check = run("--check", css, lh, backups)
        assert final_check.returncode == 0, final_check.stdout + final_check.stderr
        assert "ALREADY MODIFIED:" in final_check.stdout, final_check.stdout


exercise(NAME_COUNTRY_OLD)
exercise(NAME_LEGACY_OLD)
print("PASS: dashboard cell-padding checker and installer support both FCC Name-cell forms")
