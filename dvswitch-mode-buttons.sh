#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -Eeuo pipefail
TARGET=/usr/share/dvswitch/index.php
BACKUP_ROOT=/var/backups/dvswitch-mods/mode-buttons
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[[ $EUID -eq 0 ]] || { echo 'ERROR: Run with sudo.' >&2; exit 1; }
[[ -f $TARGET && ! -L $TARGET ]] || { echo "ERROR: Missing $TARGET" >&2; exit 1; }
python3 - "$TARGET" "${1:---check}" "$BACKUP_ROOT" "$ROOT" <<'PY'
import os, shutil, sys, tempfile
from datetime import datetime
from pathlib import Path
t, action, backups, root = map(Path, (sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]))
factory='<body style="background-color: #f8f8f8f8;font: 11pt arial, sans-serif;">'
marker='<div id="dvs-mode-buttons" aria-label="Select Mode">'
old='''<body style="background-color: #f8f8f8f8;font: 11pt arial, sans-serif;">
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
new=old.replace('<button type="button" class="button link dvs-mode-button">','<button type="button" class="button link dvs-mode-button" data-mode="',1)
# Build the functional block from the visual block so its layout remains unchanged.
new=old
for label, mode in [('BM',''),('TGIF',''),('STFU','STFU'),('YSF','YSF'),('P25','P25'),('NXDN','NXDN'),('D-Star','DSTAR')]:
    new=new.replace(f'<button type="button" class="button link dvs-mode-button">{label}</button>', f'<button type="button" class="button link dvs-mode-button" data-mode="{mode}">{label}</button>')
new += '''
<script type="text/javascript">
(function () {
  var buttons = document.querySelectorAll('#dvs-mode-buttons .dvs-mode-button');
  function markMode() {
    var rows = document.querySelectorAll('#modeInfo tr'), mode = '';
    for (var i = 0; i < rows.length; i++) {
      var head = rows[i].querySelector('th'), cell = rows[i].querySelector('td');
      if (head && cell && head.textContent.trim() === 'Mode') mode = cell.textContent.trim().toUpperCase().replace('-', '');
    }
    for (var j = 0; j < buttons.length; j++) buttons[j].classList.toggle('dvs-mode-selected', buttons[j].dataset.mode === mode && mode !== '');
  }
  for (var i = 0; i < buttons.length; i++) buttons[i].addEventListener('click', function () {
    var button = this, mode = button.dataset.mode;
    if (!mode) return;
    fetch('/dvswitch/dvswitch-mode.php', {method: 'POST', body: new URLSearchParams({mode: mode}), credentials: 'same-origin'})
      .then(function (r) { if (!r.ok) throw new Error(); return r.json(); })
      .then(function (r) { if (!r.ok) throw new Error(); markMode(); })
      .catch(function () { alert('Mode switch failed.'); });
  });
  new MutationObserver(markMode).observe(document.getElementById('modeInfo'), {childList:true, subtree:true});
  setInterval(markMode, 1000); markMode();
}());
</script>'''
data=t.read_text(encoding='utf-8')
if data.count(marker)==1 and data.count(new)==1:
 print('ALREADY MODIFIED: functional Select Mode buttons are installed. No files changed.'); raise SystemExit
if data.count(marker) not in (0,1) or data.count(factory)!=1:
 print(f'UNSUPPORTED or CUSTOMIZED: factory body={data.count(factory)}, button marker={data.count(marker)}',file=sys.stderr); raise SystemExit(1)
if action in ('--check','check'):
 print('READY: functional Select Mode button insertion target found. No files changed.'); raise SystemExit
if action not in ('--install','install'):
 print('Usage: sudo dvswitch-mode-buttons.sh --check|--install'); raise SystemExit
backups.mkdir(mode=0o700,parents=True,exist_ok=True); stamp=datetime.now().strftime('%Y%m%d-%H%M%S'); b=backups/f'install-{stamp}'; n=0
while b.exists(): n+=1; b=backups/f'install-{stamp}-{n}'
b.mkdir(mode=0o700); shutil.copy2(t,b/t.name)
if data.count(marker)==1: changed=data[:data.index(marker)]+new+data[data.index(marker)+len(old):]
else: changed=data.replace(factory,new,1)
fd,name=tempfile.mkstemp(prefix=f'.{t.name}.',dir=t.parent); os.close(fd); temp=Path(name)
try: shutil.copystat(t,temp); temp.write_text(changed,encoding='utf-8'); os.replace(temp,t)
except Exception: temp.unlink(missing_ok=True); raise
print('PASS: functional Select Mode buttons installed atomically.'); print(f'Backup: {b}')
PY

if [[ ${1:---check} == "--install" || ${1:---check} == "install" ]]; then
  install -o root -g root -m 0755 "$ROOT/lib/dvswitch-dashboard-mode" /usr/local/sbin/dvswitch-dashboard-mode
  install -o root -g root -m 0644 "$ROOT/dvswitch-mode.php" /usr/share/dvswitch/dvswitch-mode.php
  install -o root -g root -m 0440 "$ROOT/lib/dvswitch-dashboard-mode.sudoers" /etc/sudoers.d/dvswitch-dashboard-mode
  visudo -c >/dev/null
fi
