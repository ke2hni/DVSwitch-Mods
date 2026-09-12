#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI
set -u
VERSION="1.0.0"
ROOT="/usr/share/dvswitch"
INDEX_FILE="${INDEX_FILE:-$ROOT/index.php}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/dvswitch-mods/dashboard-hostname-title}"
[ "$(id -u)" -eq 0 ] || { echo "ERROR: Run with sudo." >&2; exit 1; }
python3 - "$INDEX_FILE" "${1:---check}" "$BACKUP_ROOT" <<'PY'
import os, shutil, sys, tempfile
from datetime import datetime
from pathlib import Path
index = Path(sys.argv[1]); action = sys.argv[2]; backup_root = Path(sys.argv[3])
original = '<h2>DVSwitch Dashboard</h2>'
modified = '<h2><?php echo htmlspecialchars(gethostname(), ENT_QUOTES, "UTF-8"); ?> DVSwitch Dashboard</h2>'
if not index.is_file():
    print(f"ERROR: missing file: {index}"); raise SystemExit(1)
data = index.read_text(); old_count = data.count(original); new_count = data.count(modified)
if new_count == 1 and old_count == 0:
    print("ALREADY MODIFIED: hostname-prefixed DVSwitch Dashboard title is installed. No files changed."); raise SystemExit(0)
if old_count != 1 or new_count != 0:
    print("UNSUPPORTED or CUSTOMIZED: exact dashboard title target was not found exactly once.")
    print(f"{index}: original={old_count}, modified={new_count}, expected original=1, modified=0"); raise SystemExit(1)
if action in ("--check", "check"):
    print("READY: exact original dashboard title target found. No files changed."); raise SystemExit(0)
if action not in ("--install", "install"):
    print(f"Dashboard hostname title modification {VERSION}")
    print("Usage: sudo mod-dashboard-hostname-title.sh --check|--install"); raise SystemExit(0)
backup = backup_root / f"install-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
backup.mkdir(parents=True, exist_ok=False); shutil.copy2(index, backup / index.name)
changed = data.replace(original, modified, 1)
fd, name = tempfile.mkstemp(prefix=f".{index.name}.", dir=str(index.parent)); os.close(fd); temp = Path(name)
try:
    shutil.copystat(index, temp); temp.write_text(changed); os.replace(temp, index)
except Exception:
    temp.unlink(missing_ok=True); raise
print("PASS: hostname-prefixed DVSwitch Dashboard title installed atomically.")
print(f"Backup: {backup}")
PY
