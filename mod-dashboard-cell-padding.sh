#!/usr/bin/env bash
set -u

VERSION="1.2.0"
ROOT="/usr/share/dvswitch"
CSS_FILE="${CSS_FILE:-$ROOT/css/css.php}"
LH_FILE="${LH_FILE:-$ROOT/include/lh.php}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/dvswitch-mods/dashboard-cell-padding}"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: Run with sudo." >&2; exit 1; }

python3 - "$CSS_FILE" "$LH_FILE" "${1:---check}" "$BACKUP_ROOT" <<'PY'
import os
import shutil
import sys
import tempfile
from datetime import datetime
from pathlib import Path

VERSION = "1.2.0"
css_path, lh_path = map(Path, sys.argv[1:3])
action = sys.argv[3]
backup_root = Path(sys.argv[4])

def pair(old, new, expected=1):
    return (old, new, expected)

targets = {
    css_path: [
        pair('''table th {
    font-family: "Lucidia Console",Monaco,monospace;
    text-shadow: 1px 1px #<?php echo $tableHeadDropShaddow; ?>;
    text-decoration: none;
    background: #<?php echo $backgroundBanners; ?>;
    border: 1px solid #c0c0c0;
}''', '''table th {
    font-family: "Lucidia Console",Monaco,monospace;
    text-shadow: 1px 1px #<?php echo $tableHeadDropShaddow; ?>;
    text-decoration: none;
    background: #<?php echo $backgroundBanners; ?>;
    border: 1px solid #c0c0c0;
    padding: 2px 4px;
}'''),
        pair('''table td {
    color: #000000;
    font-family: "Lucidia Console",Monaco,monospace;
    text-decoration: none;
    border: 1px solid #000000;
    overflow-x: hidden;
}''', '''table td {
    color: #000000;
    font-family: "Lucidia Console",Monaco,monospace;
    text-decoration: none;
    border: 1px solid #000000;
    overflow-x: hidden;
    padding: 2px 4px;
}'''),
    ],
    lh_path: [
        pair('echo"<td align=\\"left\\" style=\\"color:green; font-weight:bold;\\">&nbsp;$listElem[1]</td>";', 'echo"<td align=\\"left\\" style=\\"color:green; font-weight:bold;\\">$listElem[1]</td>";'),
        pair('echo "<td align=\\"left\\" style=\\"color:#464646;\\">&nbsp;<a href=\\"https://database.radioid.net/database/view?id=$listElem[2]\\" target=\\"_blank\\"><span style=\\"color:#464646;font-weight:bold;\\">$listElem[2]</span></a></td>";', 'echo "<td align=\\"left\\" style=\\"color:#464646;\\"><a href=\\"https://database.radioid.net/database/view?id=$listElem[2]\\" target=\\"_blank\\"><span style=\\"color:#464646;font-weight:bold;\\">$listElem[2]</span></a></td>";'),
        pair('echo "<td align=\\"left\\">&nbsp;<a href=\\"http://www.qrz.com/db/$listElem[2]\\" target=\\"_blank\\"><b>$listElem[2]</b></a><span style=\\"color:#464646;font-weight:bold;\\">/$listElem[3]</span></td>";', 'echo "<td align=\\"left\\"><a href=\\"http://www.qrz.com/db/$listElem[2]\\" target=\\"_blank\\"><b>$listElem[2]</b></a><span style=\\"color:#464646;font-weight:bold;\\">/$listElem[3]</span></td>";'),
        pair('echo "<td align=\\"left\\">&nbsp;<a href=\\"http://www.qrz.com/db/$listElem[2]\\" target=\\"_blank\\"><b>$listElem[2]</b></a></td>";', 'echo "<td align=\\"left\\"><a href=\\"http://www.qrz.com/db/$listElem[2]\\" target=\\"_blank\\"><b>$listElem[2]</b></a></td>";'),
        pair('echo "<td align=\\"left\\" style=\\"color:#464646;\\"><b>&nbsp;$listElem[2]</b></td>";', 'echo "<td align=\\"left\\" style=\\"color:#464646;\\"><b>$listElem[2]</b></td>";', 1),
        pair('echo \'<td align="left" style="font-weight:bold;color:#464646;">&nbsp;<b>\'.htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").\'</b></td>\';', 'echo \'<td align="left" style="font-weight:bold;color:#464646;"><b>\'.htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").\'</b></td>\';'),
        pair('echo \'<td align="left">&nbsp;<span style="color:#b5651d;font-weight:bold;white-space:normal;">\'.htmlspecialchars($dvsModsTarget, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").\'</span></td>\';', 'echo \'<td align="left"><span style="display:block;color:#b5651d;font-weight:bold;white-space:normal;">\'.htmlspecialchars($dvsModsTarget, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").\'</span></td>\';'),
    ],
}

for path in targets:
    if not path.is_file():
        print(f"ERROR: missing file: {path}")
        raise SystemExit(1)

data = {path: path.read_text() for path in targets}
states = []
for path, replacements in targets.items():
    for old, new, expected in replacements:
        states.append((path, data[path].count(old), data[path].count(new), expected))

if all(new_count == expected for _, _, new_count, expected in states):
    print("ALREADY MODIFIED: dashboard cell spacing and Target wrapping are installed. No files changed.")
    raise SystemExit(0)

if not all(old_count == expected or new_count == expected for _, old_count, new_count, expected in states):
    print("UNSUPPORTED or CUSTOMIZED: exact original activity-table targets were not found exactly once.")
    for path, old_count, new_count, expected in states:
        print(f"{path}: original={old_count}, modified={new_count}, expected={expected}")
    raise SystemExit(1)

if action in ("--check", "check"):
    print("READY: exact original dashboard cell-spacing targets found. No files changed.")
    raise SystemExit(0)

if action not in ("--install", "install"):
    print(f"Dashboard cell spacing modification {VERSION}")
    print("Usage: sudo mod-dashboard-cell-padding.sh --check|--install")
    raise SystemExit(0)

backup = backup_root / f"install-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
backup.mkdir(parents=True, exist_ok=False)
for path in targets:
    shutil.copy2(path, backup / path.name)

temporary = []
try:
    for path, replacements in targets.items():
        changed = data[path]
        for old, new, expected in replacements:
            changed = changed.replace(old, new)
        fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
        os.close(fd)
        temp = Path(name)
        shutil.copystat(path, temp)
        temp.write_text(changed)
        temporary.append((temp, path))
    for temp, path in temporary:
        os.replace(temp, path)
except Exception:
    for temp, _ in temporary:
        temp.unlink(missing_ok=True)
    raise

print("PASS: dashboard cell spacing and Target wrapping installed atomically.")
print(f"Backup: {backup}")
PY
