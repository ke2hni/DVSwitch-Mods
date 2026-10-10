#!/usr/bin/env bash
set -u

VERSION="1.2.4"
ROOT="/usr/share/dvswitch"
CSS_FILE="${CSS_FILE:-$ROOT/css/css.php}"
LH_FILE="${LH_FILE:-$ROOT/include/lh.php}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/dvswitch-mods/dashboard-cell-padding}"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: Run with sudo." >&2; exit 1; }

python3 - "$CSS_FILE" "$LH_FILE" "${1:---check}" "$BACKUP_ROOT" "${2:-}" <<'PY'
import os
import shutil
import sys
import tempfile
from datetime import datetime
from pathlib import Path

VERSION = "1.2.4"
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
        pair('echo \'<td align="left">&nbsp;<span style="color:#b5651d;font-weight:bold;white-space:normal;">\'.htmlspecialchars($dvsModsTarget, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").\'</span></td>\';', 'echo \'<td align="left"><span style="display:block;color:#b5651d;font-weight:bold;white-space:normal;">\'.htmlspecialchars($dvsModsTarget, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").\'</span></td>\';'),
    ],
}

# FCC first-name releases that add a country fallback render the same Name
# cell through $dvsModsNameHtml. Accept that form as an alternative to the
# earlier $dvsModsFirstName form; only one supported form may be present.
name_cell_alternatives = [
    pair('echo \'<td align="left" style="font-weight:bold;color:#464646;white-space:normal;overflow-wrap:anywhere;word-break:normal;width:12ch;min-width:12ch;max-width:12ch;">&nbsp;<b>\'.htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").\'</b></td>\';', 'echo \'<td align="left" style="font-weight:bold;color:#464646;white-space:normal;overflow-wrap:anywhere;word-break:normal;width:12ch;min-width:12ch;max-width:12ch;"><b>\'.htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8").\'</b></td>\';'),
    pair('echo \'<td align="left" style="font-weight:bold;color:#464646;white-space:normal;overflow-wrap:anywhere;word-break:normal;width:12ch;min-width:12ch;max-width:12ch;">&nbsp;<b>\'.$dvsModsNameHtml.\'</b></td>\';', 'echo \'<td align="left" style="font-weight:bold;color:#464646;white-space:normal;overflow-wrap:anywhere;word-break:normal;width:12ch;min-width:12ch;max-width:12ch;"><b>\'.$dvsModsNameHtml.\'</b></td>\';'),
]

for path in targets:
    if not path.is_file():
        print(f"ERROR: missing file: {path}")
        raise SystemExit(1)

data = {}
newline_by_path = {}
for path in targets:
    raw = path.read_bytes()
    if b"\r" in raw.replace(b"\r\n", b""):
        print(f"ERROR: refusing mixed line endings in {path}")
        raise SystemExit(1)
    newline = b"\r\n" if b"\r\n" in raw else b"\n"
    newline_by_path[path] = newline
    data[path] = raw.decode("utf-8").replace("\r\n", "\n")

def encoded_content(path, content):
    encoded = content.encode("utf-8")
    if newline_by_path[path] == b"\r\n":
        encoded = encoded.replace(b"\n", b"\r\n")
    return encoded
states = []
for path, replacements in targets.items():
    for old, new, expected in replacements:
        states.append((path, data[path].count(old), data[path].count(new), expected))

name_states = [(lh_path, data[lh_path].count(old), data[lh_path].count(new), expected)
               for old, new, expected in name_cell_alternatives]

def one_supported_state(old_count, new_count, expected):
    return (old_count == expected and new_count == 0) or (old_count == 0 and new_count == expected)

active_name_states = [state for state in name_states if state[1] or state[2]]
name_state_valid = len(active_name_states) == 1 and one_supported_state(*active_name_states[0][1:])
name_state_modified = name_state_valid and active_name_states[0][1] == 0

if action not in ("--restore", "restore") and all(new_count == expected for _, _, new_count, expected in states) and name_state_modified:
    print("ALREADY MODIFIED: dashboard cell spacing and Target wrapping are installed. No files changed.")
    raise SystemExit(0)

if action not in ("--restore", "restore") and (not all(one_supported_state(old_count, new_count, expected) for _, old_count, new_count, expected in states) or not name_state_valid):
    print("UNSUPPORTED or CUSTOMIZED: exact original activity-table targets were not found exactly once.")
    for path, old_count, new_count, expected in states:
        print(f"{path}: original={old_count}, modified={new_count}, expected={expected}")
    if not name_state_valid:
        for path, old_count, new_count, expected in name_states:
            print(f"{path} (FCC Name cell alternative): original={old_count}, modified={new_count}, expected={expected}")
    raise SystemExit(1)

if action in ("--restore", "restore"):
    if len(sys.argv) < 6 or not sys.argv[5]:
        print("Usage: sudo mod-dashboard-cell-padding.sh --restore BACKUP-NAME")
        raise SystemExit(2)
    backup = backup_root / sys.argv[5]
    if not backup.is_dir() or backup.is_symlink():
        print(f"ERROR: protected backup is unavailable: {backup}")
        raise SystemExit(1)
    for path in targets:
        if not (backup / path.name).is_file():
            print(f"ERROR: protected backup is incomplete: {backup / path.name}")
            raise SystemExit(1)
    if not all(new_count == expected for _, _, new_count, expected in states) or not name_state_modified:
        print("ERROR: refusing restore; one or more owned cell-padding edits are missing or customized.")
        raise SystemExit(1)
    modified_name = next(((old, new, expected) for old, new, expected in name_cell_alternatives
                          if data[lh_path].count(new) == expected), None)
    if modified_name is None:
        print("ERROR: refusing restore; FCC Name cell edit is missing or customized.")
        raise SystemExit(1)
    changed_by_path = {path: data[path] for path in targets}
    for path, replacements in targets.items():
        for old, new, expected in replacements:
            changed_by_path[path] = changed_by_path[path].replace(new, old, expected)
    old, new, expected = modified_name
    changed_by_path[lh_path] = changed_by_path[lh_path].replace(new, old, expected)
    temporary = []
    try:
        for path, changed in changed_by_path.items():
            fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
            os.close(fd)
            temp = Path(name)
            shutil.copystat(path, temp)
            temp.write_bytes(encoded_content(path, changed))
            temporary.append((temp, path))
        for temp, path in temporary:
            os.replace(temp, path)
    except Exception:
        for temp, _ in temporary:
            temp.unlink(missing_ok=True)
        raise
    print(f"PASS: restored only cell-padding edits from {backup}; unrelated changes were preserved.")
    raise SystemExit(0)

if action in ("--check", "check"):
    print("READY: exact original dashboard cell-spacing targets found. No files changed.")
    raise SystemExit(0)

if action not in ("--install", "install"):
    print(f"Dashboard cell spacing modification {VERSION}")
    print("Usage: sudo mod-dashboard-cell-padding.sh --check|--install|--restore BACKUP-NAME")
    raise SystemExit(2)

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
        if path == lh_path:
            for old, new, expected in name_cell_alternatives:
                changed = changed.replace(old, new)
        fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
        os.close(fd)
        temp = Path(name)
        shutil.copystat(path, temp)
        temp.write_bytes(encoded_content(path, changed))
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
