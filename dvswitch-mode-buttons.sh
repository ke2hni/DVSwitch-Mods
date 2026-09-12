#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI

set -u

VERSION="2.3.0"
ROOT="/usr/share/dvswitch"
INDEX_FILE="${INDEX_FILE:-$ROOT/index.php}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/dvswitch-mods/mode-buttons}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: Run with sudo." >&2; exit 1; }

python3 - "$INDEX_FILE" "${1:---check}" "$BACKUP_ROOT" "$SCRIPT_DIR" <<'PY'
import os, shutil, sys, tempfile
from datetime import datetime
from pathlib import Path

index = Path(sys.argv[1])
action = sys.argv[2]
backup_root = Path(sys.argv[3])
repo_root = Path(sys.argv[4])
helper_src = repo_root / 'lib' / 'dvswitch-dashboard-mode'
dmr_helper_src = repo_root / 'lib' / 'dvswitch-dashboard-dmr-network'
php_src = repo_root / 'dvswitch-mode.php'
sudoers_src = repo_root / 'lib' / 'dvswitch-dashboard-mode.sudoers'

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
  left: max(8px, calc((100vw - 1200px) / 4 - 56px));
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
  background-color: #008000;
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
  background-color: #008000;
}
@media (max-width: 1450px) {
  #dvs-mode-buttons { display: none; }
}
</style>
<script type="text/javascript">
(function () {
  var rail = document.getElementById('dvs-mode-buttons');
  var buttons = document.querySelectorAll('#dvs-mode-buttons .dvs-mode-button');
  function centerRailWithStatus() {
    var status = document.getElementById('modeInfo');
    if (!rail || !status) return;
    var box = status.getBoundingClientRect();
    rail.style.top = (box.top + box.height / 2) + 'px';
  }
  for (var i = 0; i < buttons.length; i++) {
    buttons[i].addEventListener('click', function () {
      for (var j = 0; j < buttons.length; j++) {
        buttons[j].classList.remove('dvs-mode-selected');
      }
      var button = this;
      var modeMap = {BM: 'BM', TGIF: 'TGIF', P25: 'P25', YSF: 'YSF', NXDN: 'NXDN', 'D-Star': 'DSTAR', STFU: 'STFU'};
      var commandMode = modeMap[button.dataset.mode];
      if (!commandMode) return;
      button.disabled = true;
      var body = new URLSearchParams(); body.set('mode', commandMode);
      fetch('/dvswitch/dvswitch-mode.php', {method: 'POST', body: body, credentials: 'same-origin'})
        .then(function (response) { if (!response.ok) throw new Error('switch failed'); return response.json(); })
        .then(function (result) {
          if (!result.ok) throw new Error('switch rejected');
          for (var k = 0; k < buttons.length; k++) buttons[k].classList.remove('dvs-mode-selected');
          button.classList.add('dvs-mode-selected');
        })
        .catch(function () { alert('Mode switch failed. The current mode was not changed visually.'); })
        .finally(function () { button.disabled = false; });
    });
  }
  window.addEventListener('resize', centerRailWithStatus);
  setTimeout(centerRailWithStatus, 0);
  setInterval(centerRailWithStatus, 1000);
}());
</script>'''

if not index.is_file():
    print(f"ERROR: missing file: {index}"); raise SystemExit(1)
data = index.read_text()
marker = '<div id="dvs-mode-buttons" aria-label="Select Mode">'
original_count = data.count(original)
added_count = data.count(marker)
current_count = data.count(added)
has_current_centering = data.count('function centerRailWithStatus()') == 1
has_current_color = data.count('background-color: #008000;') == 2
has_visual_v104_click = data.count("this.classList.add('dvs-mode-selected');") == 1
has_functional_v2001 = data.count("fetch('/dvswitch/dvswitch-mode.php'") == 1 and data.count("['P25','YSF','NXDN','DSTAR','STFU']") == 1
has_functional_v210 = data.count("var modeMap = {BM: 'BM', TGIF: 'TGIF'") == 1
has_known_rail_structure = (
    data.count('id="dvs-mode-buttons"') == 1 and
    data.count('class="dvs-mode-buttons-title"') == 1 and
    all(data.count(f'data-mode="{mode}"') == 1 for mode in ('BM', 'TGIF', 'STFU', 'YSF', 'P25', 'NXDN', 'D-Star')) and
    data.count('function centerRailWithStatus()') == 1
)
upgrade = False
if added_count == 1 and current_count == 1 and has_current_centering and has_current_color:
    print("ALREADY MODIFIED: visual Select Mode buttons are installed. No files changed."); raise SystemExit(0)
if added_count == 1:
    legacy_markers = (
        data.count('left: max(8px, calc(50% - 740px));') == 1,
        data.count('background-color: #356244;') == 2,
        data.count("this.classList.add('dvs-mode-selected');") == 1,
    )
    visual_v104_markers = (
        data.count('left: max(8px, calc((100vw - 1200px) / 4 - 56px));') == 1,
        has_current_centering,
        has_current_color,
        has_visual_v104_click,
    )
    functional_v2001_markers = (
        has_current_centering,
        has_current_color,
        has_functional_v2001,
    )
    functional_v210_markers = (has_current_centering, has_current_color, has_functional_v210)
    if not all(legacy_markers) and not all(visual_v104_markers) and not all(functional_v2001_markers) and not all(functional_v210_markers) and not has_known_rail_structure:
        print("UNSUPPORTED or CUSTOMIZED: existing mode-button block is not a recognized prior version.")
        raise SystemExit(1)
    upgrade = True
elif original_count != 1:
    print("UNSUPPORTED or CUSTOMIZED: exact dashboard body insertion target was not found exactly once.")
    print(f"{index}: original body={original_count}, mode-button marker={added_count}, expected original body=1, marker=0")
    raise SystemExit(1)
for required in (helper_src, dmr_helper_src, php_src, sudoers_src):
    if not required.is_file():
        print(f"ERROR: required repository file missing: {required}"); raise SystemExit(1)
if action in ("--check", "check"):
    print("PASS: mode-switch backend source files are present. No files changed.")
    if upgrade:
        print("READY: recognized earlier Select Mode button version can be upgraded. No files changed.")
    else:
        print("READY: exact dashboard body insertion target found. No files changed.")
    raise SystemExit(0)
if action not in ("--install", "install", "apply"):
    print(f"DVSwitch visual mode buttons {VERSION}")
    print("Usage: sudo dvswitch-mode-buttons.sh --check|--install|apply"); raise SystemExit(0)

backup = backup_root / f"install-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
backup.mkdir(parents=True, exist_ok=False)
shutil.copy2(index, backup / index.name)
for src, dest in ((helper_src, Path('/usr/local/sbin/dvswitch-dashboard-mode')), (dmr_helper_src, Path('/usr/local/sbin/dvswitch-dashboard-dmr-network')), (php_src, Path('/usr/share/dvswitch/dvswitch-mode.php')), (sudoers_src, Path('/etc/sudoers.d/dvswitch-dashboard-mode'))):
    if dest.exists(): shutil.copy2(dest, backup / dest.name)
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name('.' + dest.name + '.tmp')
    shutil.copy2(src, tmp)
    os.chmod(tmp, 0o755 if dest.name == 'dvswitch-dashboard-mode' else 0o644)
    os.replace(tmp, dest)
if upgrade:
    start = data.index(marker)
    end = data.index('</script>', start) + len('</script>')
    changed = data[:start] + added.split('\n', 1)[1] + data[end:]
else:
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
