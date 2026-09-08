#!/usr/bin/env bash
set -u

VERSION="1.0.0"
CSS_FILE="${CSS_FILE:-/usr/share/dvswitch/css/css.php}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/dvswitch-mods/dashboard-cell-padding}"

die(){ echo "ERROR: $*" >&2; exit 1; }

require_root(){
  [ "$(id -u)" -eq 0 ] || die "Run with sudo."
}

count_text(){
  local text="$1" file="$2"
  python3 - "$text" "$file" <<'PY'
import sys
from pathlib import Path
needle = sys.argv[1]
data = Path(sys.argv[2]).read_text()
print(data.count(needle))
PY
}

patch_file(){
  local source="$1" destination="$2"
  python3 - "$source" "$destination" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
data = source.read_text()

original_th = '''table th {
    font-family: "Lucidia Console",Monaco,monospace;
    text-shadow: 1px 1px #<?php echo $tableHeadDropShaddow; ?>;
    text-decoration: none;
    background: #<?php echo $backgroundBanners; ?>;
    border: 1px solid #c0c0c0;
}'''

original_td = '''table td {
    color: #000000;
    font-family: "Lucidia Console",Monaco,monospace;
    text-decoration: none;
    border: 1px solid #000000;
    overflow-x: hidden;
}'''

modified_th = '''table th {
    font-family: "Lucidia Console",Monaco,monospace;
    text-shadow: 1px 1px #<?php echo $tableHeadDropShaddow; ?>;
    text-decoration: none;
    background: #<?php echo $backgroundBanners; ?>;
    border: 1px solid #c0c0c0;
    padding: 2px 4px;
}'''

modified_td = '''table td {
    color: #000000;
    font-family: "Lucidia Console",Monaco,monospace;
    text-decoration: none;
    border: 1px solid #000000;
    overflow-x: hidden;
    padding: 2px 4px;
}'''

if data.count(original_th) != 1 or data.count(original_td) != 1:
    raise SystemExit("exact original blocks changed or ambiguous")

data = data.replace(original_th, modified_th, 1)
data = data.replace(original_td, modified_td, 1)
destination.write_text(data)
PY
}

check(){
  [ -f "$CSS_FILE" ] || die "Missing file: $CSS_FILE"
  local original_th original_td modified_th modified_td
  original_th=$(cat <<'EOF'
table th {
    font-family: "Lucidia Console",Monaco,monospace;
    text-shadow: 1px 1px #<?php echo $tableHeadDropShaddow; ?>;
    text-decoration: none;
    background: #<?php echo $backgroundBanners; ?>;
    border: 1px solid #c0c0c0;
}
EOF
)
  original_td=$(cat <<'EOF'
table td {
    color: #000000;
    font-family: "Lucidia Console",Monaco,monospace;
    text-decoration: none;
    border: 1px solid #000000;
    overflow-x: hidden;
}
EOF
)
  modified_th=$(cat <<'EOF'
table th {
    font-family: "Lucidia Console",Monaco,monospace;
    text-shadow: 1px 1px #<?php echo $tableHeadDropShaddow; ?>;
    text-decoration: none;
    background: #<?php echo $backgroundBanners; ?>;
    border: 1px solid #c0c0c0;
    padding: 2px 4px;
}
EOF
)
  modified_td=$(cat <<'EOF'
table td {
    color: #000000;
    font-family: "Lucidia Console",Monaco,monospace;
    text-decoration: none;
    border: 1px solid #000000;
    overflow-x: hidden;
    padding: 2px 4px;
}
EOF
)

  if [ "$(count_text "$modified_th" "$CSS_FILE")" -eq 1 ] && [ "$(count_text "$modified_td" "$CSS_FILE")" -eq 1 ]; then
    echo "ALREADY MODIFIED: dashboard table-cell padding is installed. No files changed."
    return 0
  fi
  local th_count td_count
  th_count="$(count_text "$original_th" "$CSS_FILE")"
  td_count="$(count_text "$original_td" "$CSS_FILE")"
  if [ "$th_count" -ne 1 ] || [ "$td_count" -ne 1 ]; then
    echo "UNSUPPORTED or CUSTOMIZED: exact original table-cell blocks were not found exactly once."
    echo "table th matches: $th_count"
    echo "table td matches: $td_count"
    return 1
  fi
  echo "READY: exact original table-cell blocks found. No files changed."
}

install_mod(){
  require_root
  local check_output
  check_output="$(check)" || { echo "$check_output"; return 1; }
  echo "$check_output" | grep -q '^ALREADY MODIFIED:' && return 0
  local stamp backup temp
  stamp="$(date +%Y%m%d-%H%M%S)"
  backup="$BACKUP_ROOT/install-$stamp"
  temp="$(mktemp "$CSS_FILE.tmp.XXXXXX")" || die "Could not create temporary file"
  trap 'rm -f "$temp"' RETURN
  mkdir -p "$backup" || die "Could not create backup directory"
  cp -a "$CSS_FILE" "$backup/css.php" || die "Could not create backup"
  patch_file "$CSS_FILE" "$temp" || die "Could not create patched file"
  chown --reference="$CSS_FILE" "$temp" || die "Could not preserve ownership"
  chmod --reference="$CSS_FILE" "$temp" || die "Could not preserve permissions"
  mv -f "$temp" "$CSS_FILE" || die "Could not install patched file"
  trap - RETURN
  echo "PASS: dashboard table-cell padding installed atomically."
  echo "Backup: $backup"
}

case "${1:---check}" in
  --check) check ;;
  --install) install_mod ;;
  --help|-h)
    echo "Dashboard table-cell padding modification $VERSION"
    echo "Usage: sudo $0 --check|--install"
    ;;
  *) die "Usage: sudo $0 --check|--install" ;;
esac
