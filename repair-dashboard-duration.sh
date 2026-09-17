#!/usr/bin/env bash
set -Eeuo pipefail

TARGET=/usr/share/dvswitch/include/functions.php
[[ $EUID -eq 0 ]] || { echo 'ERROR: run with sudo' >&2; exit 1; }
[[ -f "$TARGET" ]] || { echo "ERROR: missing $TARGET" >&2; exit 1; }

python3 - "$TARGET" "${1:---check}" <<'PY'
import re, shutil, sys
from pathlib import Path

path = Path(sys.argv[1])
action = sys.argv[2]
text = path.read_text(encoding='utf-8')
marker = '// DVSwitch-Mods: dashboard duration type repair v2'
if text.count(marker) > 1:
    raise SystemExit('ERROR: ambiguous dashboard duration repair')
if marker in text or re.search(r'ceil\s*\(\s*\(float\)\s*\$listElem\[6\]\s*\)', text):
    print('ALREADY REPAIRED: dashboard duration handling is installed.')
    raise SystemExit(0)

pattern = re.compile(r'''(?P<indent>\s*)\$timestamp->add\(new DateInterval\(\s*'PT'\s*\.\s*ceil\(\s*\$listElem\[6\]\s*\)\s*\.\s*'S'\s*\)\s*\);''')
match = pattern.search(text)
if not match:
    raise SystemExit('ERROR: stock duration target not found')
if action == '--check':
    print('READY: dashboard duration repair available; no files changed.')
    raise SystemExit(0)
if action != '--install':
    raise SystemExit('ERROR: usage: repair-dashboard-duration-v2.sh [--check|--install]')

backup = path.with_name(path.name + '.before-dashboard-duration-repair-v2')
if backup.exists():
    raise SystemExit(f'ERROR: backup already exists: {backup}')
shutil.copy2(path, backup)
replacement = (match.group('indent') + '// ' + marker + '\n' + match.group('indent') +
               'if (!is_numeric($listElem[6])) { return $mode; }\n' +
               match.group(0).replace('ceil($listElem[6])', 'ceil((float)$listElem[6])'))
path.write_text(text[:match.start()] + replacement + text[match.end():], encoding='utf-8')
print(f'PASS: dashboard duration repair installed. Backup: {backup}')
PY

php -l "$TARGET" >/dev/null || { echo 'ERROR: PHP validation failed; restore the v2 backup.' >&2; exit 1; }
