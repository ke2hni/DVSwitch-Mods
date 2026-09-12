#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

set -u

VERSION="1.0.0"
ROOT="/usr/share/dvswitch"
INDEX_FILE="${INDEX_FILE:-$ROOT/index.php}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/dvswitch-mods/mode-buttons}"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: Run with sudo." >&2; exit 1; }

python3 - "$INDEX_FILE" "${1:---check}" "$BACKUP_ROOT" <<'PY'
import os, shutil, sys, tempfile
from datetime import datetime
from pathlib import Path

index = Path(sys.argv[1])
action = sys.argv[2]
backup_root = Path(sys.argv[3])

original = '<body style="background-color: #f8f8f8f8;font: 11pt arial, sans-serif;">'
added = '''<body style="background-color: #f8f8f8f8;font: 11pt arial, sans-serif;">
<div id="dvs-mode-buttons" aria-label="Select Mode">
<div class="dvs-mode-buttons-title">Select Mode</div>
<button type="button" class="button link dvs-mode-button" data-mode="BM">BM</button>
<button type="button" class="button link dvs-mode-button" data-mode="TGIF">TGIF</button>
<button type="button" class="button link dvs-mode-button" data-mode="STFU">STFU</button>
<button type="button" class="button link dvs-mode-button" data-mode="YSF">YSF</button>
<button type="button" class="button link dvs-mode-button" data-mode="P25">P25</button>
<button type="button" class="button link dvs-mode-button" data-mode="NXDN">NXDN</button>
<button type="button" class="button link dvs-mode-button" data-mode="D-Star">D-Star</button>
</div>
<style type="text/css">
#dvs-mode-buttons {
  position: fixed;
  z-index: 30;
  left: max(8px, calc(50% - 740px));
  top: 50%;
  transform: translateY(-50%);
  width: 112px;
  text-align: center;
}
#dvs-mode-buttons .dvs-mode-buttons-title {
  margin: 0 0 8px;
  color: inherit;
  font-weight: bold;
  text-align: center;
  white-space: nowrap;
}
#dvs-mode-buttons .dvs-mode-button {
  box-sizing: border-box;
  display: block;
  width: 112px;
  height: 32px;
  margin: 4px 0;
  padding: 0;
  line-height: 32px;
  text-align: center;
  vertical-align: middle;
}
#dvs-mode-buttons .dvs-mode-button.dvs-mode-selected {
  background-color: #356244;
  color: white;
}
#dvs-mode-buttons .dvs-mode-button:focus-visible {
  outline: 2px solid #f0c419;
  outline-offset: 2px;
}
#dvs-mode-buttons .dvs-mode-button:hover {
  background-color: #3a87cd;
}
#dvs-mode-buttons .dvs-mode-button.dvs-mode-selected:hover {
  background-color: #356244;
}
@media (max-width: 1450px) {
  #dvs-mode-buttons { display: none; }
}
</style>
<script type="text/javascript">
(function () {
  var buttons = document.querySelectorAll('#dvs-mode-buttons .dvs-mode-button');
  for (var i = 0; i < buttons.length; i++) {
    buttons[i].addEventListener('click', function () {
      for (var j = 0; j < buttons.length; j++) {
        buttons[j].classList.remove('dvs-mode-selected');
      }
      this.classList.add('dvs-mode-selected');
    });
  }
}());
</script>'''

if not index.is_file():
    print(f"ERROR: missing file: {index}"); raise SystemExit(1)
data = index.read_text()
marker = '<div id="dvs-mode-buttons" aria-label="Select Mode">'
original_count = data.count(original)
added_count = data.count(marker)
if added_count == 1 and data.count(added) == 1:
    print("ALREADY MODIFIED: visual Select Mode buttons are installed. No files changed."); raise SystemExit(0)
if original_count != 1 or added_count != 0:
    print("UNSUPPORTED or CUSTOMIZED: exact dashboard body insertion target was not found exactly once.")
    print(f"{index}: original body={original_count}, mode-button marker={added_count}, expected original body=1, marker=0")
    raise SystemExit(1)
if action in ("--check", "check"):
    print("READY: exact dashboard body insertion target found. No files changed."); raise SystemExit(0)
if action not in ("--install", "install", "apply"):
    print(f"DVSwitch visual mode buttons {VERSION}")
    print("Usage: sudo dvswitch-mode-buttons.sh --check|--install|apply"); raise SystemExit(0)

backup = backup_root / f"install-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
backup.mkdir(parents=True, exist_ok=False)
shutil.copy2(index, backup / index.name)
changed = data.replace(original, added, 1)
fd, name = tempfile.mkstemp(prefix=f".{index.name}.", dir=str(index.parent)); os.close(fd)
temp = Path(name)
try:
    shutil.copystat(index, temp); temp.write_text(changed); os.replace(temp, index)
except Exception:
    temp.unlink(missing_ok=True); raise
print("PASS: visual Select Mode button rail installed atomically.")
print(f"Backup: {backup}")
PY
