#!/usr/bin/env python3
"""Verify targeted restores for the manager's previously mismatched actions."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(script: str, action: str, backup_name: str, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(ROOT / script), action, backup_name], env=env,
                          text=True, capture_output=True)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("FAIL: " + message)


with tempfile.TemporaryDirectory(prefix="dvsm-targeted-restore-") as tmp:
    root = Path(tmp)

    index = root / "index.php"
    index.write_text("<title>DVSwitch Dashboard</title>\n<h2>DVSwitch Dashboard</h2>\n")
    hostname_backups = root / "hostname-backups"
    env = os.environ | {"INDEX_FILE": str(index), "BACKUP_ROOT": str(hostname_backups)}
    installed = subprocess.run(["bash", str(ROOT / "mod-dashboard-hostname-title.sh"), "--install"],
                               env=env, text=True, capture_output=True)
    require(installed.returncode == 0, "hostname-title install failed: " + installed.stderr)
    backup_name = next(hostname_backups.iterdir()).name
    installed_content = index.read_text()
    drifted = installed_content.replace('DVSwitch Dashboard</h2>', 'Customized Dashboard</h2>')
    index.write_text(drifted)
    refused = run("mod-dashboard-hostname-title.sh", "--restore", backup_name, env)
    require(refused.returncode != 0, "hostname-title restore accepted a customized owned heading")
    require(index.read_text() == drifted, "failed hostname-title restore changed index.php")
    index.write_text(installed_content + "<!-- unrelated dashboard edit -->\n")
    restored = run("mod-dashboard-hostname-title.sh", "--restore", backup_name, env)
    require(restored.returncode == 0, "hostname-title restore failed: " + restored.stderr)
    content = index.read_text()
    require("<title>DVSwitch Dashboard</title>" in content and "<h2>DVSwitch Dashboard</h2>" in content,
            "hostname-title restore did not reverse owned fragments")
    require("unrelated dashboard edit" in content, "hostname-title restore erased an unrelated edit")

    index.write_text("<title>DVSwitch Dashboard</title>\n<h2>DVSwitch Dashboard</h2>\n")
    css = root / "css.php"
    lh = root / "lh.php"
    css.write_text('''table th {\n    font-family: "Lucidia Console",Monaco,monospace;\n    text-shadow: 1px 1px #<?php echo $tableHeadDropShaddow; ?>;\n    text-decoration: none;\n    background: #<?php echo $backgroundBanners; ?>;\n    border: 1px solid #c0c0c0;\n}\ntable td {\n    color: #000000;\n    font-family: "Lucidia Console",Monaco,monospace;\n    text-decoration: none;\n    border: 1px solid #000000;\n    overflow-x: hidden;\n}\n''')
    lh.write_text('''echo"<td align=\\"left\\" style=\\"color:green; font-weight:bold;\\">&nbsp;$listElem[1]</td>";\necho "<td align=\\"left\\" style=\\"color:#464646;\\">&nbsp;<a href=\\"https://database.radioid.net/database/view?id=$listElem[2]\\" target=\\"_blank\\"><span style=\\"color:#464646;font-weight:bold;\\">$listElem[2]</span></a></td>";\necho "<td align=\\"left\\">&nbsp;<a href=\\"http://www.qrz.com/db/$listElem[2]\\" target=\\"_blank\\"><b>$listElem[2]</b></a><span style=\\"color:#464646;font-weight:bold;\\">/$listElem[3]</span></td>";\necho "<td align=\\"left\\">&nbsp;<a href=\\"http://www.qrz.com/db/$listElem[2]\\" target=\\"_blank\\"><b>$listElem[2]</b></a></td>";\necho "<td align=\\"left\\" style=\\"color:#464646;\\"><b>&nbsp;$listElem[2]</b></td>";\necho '<td align="left">&nbsp;<span style="color:#b5651d;font-weight:bold;white-space:normal;">'.htmlspecialchars($dvsModsTarget, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").'</span></td>';\necho '<td align="left" style="font-weight:bold;color:#464646;white-space:normal;overflow-wrap:anywhere;word-break:normal;width:12ch;min-width:12ch;max-width:12ch;">&nbsp;<b>'.htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").'</b></td>';\n''')
    cell_backups = root / "cell-backups"
    env = os.environ | {"CSS_FILE": str(css), "LH_FILE": str(lh), "BACKUP_ROOT": str(cell_backups)}
    installed = subprocess.run(["bash", str(ROOT / "mod-dashboard-cell-padding.sh"), "--install"],
                               env=env, text=True, capture_output=True)
    require(installed.returncode == 0, "cell-padding install failed: " + installed.stdout + installed.stderr)
    backup_name = next(cell_backups.iterdir()).name
    installed_css = css.read_text()
    installed_lh = lh.read_text()
    drifted_css = installed_css.replace("padding: 2px 4px;", "padding: 3px 4px;", 1)
    css.write_text(drifted_css)
    refused = run("mod-dashboard-cell-padding.sh", "--restore", backup_name, env)
    require(refused.returncode != 0, "cell-padding restore accepted a customized owned CSS edit")
    require(css.read_text() == drifted_css and lh.read_text() == installed_lh,
            "failed cell-padding restore changed one of the dashboard files")
    css.write_text(installed_css + "/* unrelated CSS edit */\n")
    lh.write_text(installed_lh + "// unrelated activity edit\n")
    restored = run("mod-dashboard-cell-padding.sh", "--restore", backup_name, env)
    require(restored.returncode == 0, "cell-padding restore failed: " + restored.stdout + restored.stderr)
    require("padding: 2px 4px" not in css.read_text(), "cell-padding CSS edit remained after restore")
    require("unrelated CSS edit" in css.read_text() and "unrelated activity edit" in lh.read_text(),
            "cell-padding restore erased unrelated edits")

print("PASS: hostname-title and cell-padding manager restores reverse only owned edits")
