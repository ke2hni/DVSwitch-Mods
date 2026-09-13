#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

set -Eeuo pipefail
readonly VERSION="1.0.0"
readonly TARGET="/usr/share/dvswitch/index.php"
readonly BACKUP_ROOT="/var/backups/dvswitch-mods/mode-buttons"

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "ERROR: Run with sudo." >&2; exit 1; }
[[ -f "$TARGET" && ! -L "$TARGET" ]] || { echo "ERROR: Required regular file not found: $TARGET" >&2; exit 1; }

python3 - "$TARGET" "${1:---check}" "$BACKUP_ROOT" <<'PY'
import os, shutil, sys, tempfile
from datetime import datetime
from pathlib import Path

target, action, backup_root = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
factory = '<body style="background-color: #f8f8f8f8;font: 11pt arial, sans-serif;">'
marker = '<div id="dvs-mode-buttons" aria-label="Select Mode">'
block = '''<body style="background-color: #f8f8f8f8;font: 11pt arial, sans-serif;">
<div id="dvs-mode-buttons" aria-label="Select Mode">
<div class="dvs-mode-buttons-title">Select Mode</div>
<button type="button" class="button link dvs-mode-button">BM</button>
<button type="button" class="button link dvs-mode-button">TGIF</button>
<button type="button" class="button link dvs-mode-button">STFU</button>
<button type="button" class="button link dvs-mode-button">YSF</button>
<button type="button" class="button link dvs-mode-button">P25</button>
<button type="button" class="button link dvs-mode-button">NXDN</button>
<button type="button" class="button link dvs-mode-button">D-Star</button>
</div>
<style type="text/css">
#dvs-mode-buttons { position: fixed; z-index: 30; left: max(8px, calc(50% - 740px)); top: 50%; transform: translateY(-50%); width: 112px; text-align: center; }
#dvs-mode-buttons .dvs-mode-buttons-title { margin: 0 0 8px; color: inherit; font-weight: bold; text-align: center; white-space: nowrap; }
#dvs-mode-buttons .dvs-mode-button { box-sizing: border-box; display: block; width: 112px; height: 32px; margin: 4px 0; padding: 0; line-height: 32px; text-align: center; vertical-align: middle; }
@media (max-width: 1450px) { #dvs-mode-buttons { display: none; } }
</style>'''
data = target.read_text(encoding="utf-8")
if data.count(marker) == 1 and data.count(block) == 1:
    print("ALREADY MODIFIED: visual Select Mode buttons are installed. No files changed."); raise SystemExit(0)
if data.count(marker) != 0 or data.count(factory) != 1:
    print(f"UNSUPPORTED or CUSTOMIZED: exact factory dashboard insertion target was not found exactly once. factory body={data.count(factory)}, button marker={data.count(marker)}", file=sys.stderr); raise SystemExit(1)
if action in ("--check", "check"):
    print("READY: exact factory dashboard insertion target found. No files changed."); raise SystemExit(0)
if action not in ("--install", "install"):
    print(f"Visual Select Mode buttons {VERSION}\nUsage: sudo dvswitch-mode-buttons.sh --check|--install"); raise SystemExit(0)
stamp = datetime.now().strftime('%Y%m%d-%H%M%S')
backup_root.mkdir(mode=0o700, parents=True, exist_ok=True)
backup = backup_root / f"install-{stamp}"; suffix = 0
while backup.exists(): suffix += 1; backup = backup_root / f"install-{stamp}-{suffix}"
backup.mkdir(mode=0o700); shutil.copy2(target, backup / target.name)
temporary = Path(tempfile.mkstemp(prefix=f".{target.name}.", dir=target.parent)[1])
try:
    shutil.copystat(target, temporary); temporary.write_text(data.replace(factory, block, 1), encoding="utf-8"); os.replace(temporary, target)
except Exception:
    temporary.unlink(missing_ok=True); raise
print("PASS: visual Select Mode buttons installed atomically.")
print(f"Backup: {backup}")
PY
