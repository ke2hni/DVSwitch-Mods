#!/usr/bin/env bash
set -u

VERSION="1.0"
ROOT="/usr/share/dvswitch"

STAMP="$(date +%Y%m%d-%H%M%S)"
ORIGINAL_BACKUP_DIR="$ROOT/.dvs-dashboard-display-original"
RUN_BACKUP_DIR="$ROOT/.dvs-dashboard-display-backup-$STAMP"
LOG_FILE="$HOME/dvs-dashboard-display-$STAMP.log"

INDEX_FILE="$ROOT/index.php"
CSS_FILE="$ROOT/css/css.php"
LH_FILE="$ROOT/include/lh.php"
LOCALTX_FILE="$ROOT/include/localtx.php"
SYSTEM_FILE="$ROOT/include/system.php"

log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
die(){ log "ERROR: $*"; exit 1; }

need_root(){
  if [ "$(id -u)" -ne 0 ]; then
    die "Run with sudo."
  fi
}

require_file(){
  [ -f "$1" ] || die "Missing required file: $1"
}

copy_dashboard_files_to(){
  dest="$1"
  mkdir -p "$dest" || die "Could not create backup directory: $dest"

  cp -a "$INDEX_FILE" "$dest/index.php" || die "Could not backup index.php"
  cp -a "$CSS_FILE" "$dest/css.php" || die "Could not backup css.php"
  cp -a "$LH_FILE" "$dest/lh.php" || die "Could not backup lh.php"
  cp -a "$LOCALTX_FILE" "$dest/localtx.php" || die "Could not backup localtx.php"
  cp -a "$SYSTEM_FILE" "$dest/system.php" || die "Could not backup system.php"
}

restore_dashboard_files_from(){
  src="$1"

  [ -f "$src/index.php" ] || die "Backup missing index.php"
  [ -f "$src/css.php" ] || die "Backup missing css.php"
  [ -f "$src/lh.php" ] || die "Backup missing lh.php"
  [ -f "$src/localtx.php" ] || die "Backup missing localtx.php"
  [ -f "$src/system.php" ] || die "Backup missing system.php"

  cp -a "$src/index.php" "$INDEX_FILE" || die "Could not restore index.php"
  cp -a "$src/css.php" "$CSS_FILE" || die "Could not restore css.php"
  cp -a "$src/lh.php" "$LH_FILE" || die "Could not restore lh.php"
  cp -a "$src/localtx.php" "$LOCALTX_FILE" || die "Could not restore localtx.php"
  cp -a "$src/system.php" "$SYSTEM_FILE" || die "Could not restore system.php"
}

ensure_original_backup(){
  if [ -d "$ORIGINAL_BACKUP_DIR" ]; then
    log "Protected original backup already exists and will NOT be overwritten: $ORIGINAL_BACKUP_DIR"
    return 0
  fi

  log "Creating protected original dashboard backup: $ORIGINAL_BACKUP_DIR"
  copy_dashboard_files_to "$ORIGINAL_BACKUP_DIR"

  {
    echo "DVSwitch Dashboard Display Layout original backup"
    echo "Created: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Script version: $VERSION"
    echo "This directory is intentionally preserved and should not be overwritten by later apply runs."
  } > "$ORIGINAL_BACKUP_DIR/README.txt" || true
}

create_run_backup(){
  log "Creating per-run backup: $RUN_BACKUP_DIR"
  copy_dashboard_files_to "$RUN_BACKUP_DIR"
}

replace_or_confirm(){
  file="$1"
  old="$2"
  new="$3"
  label="$4"

  if grep -Fq "$old" "$file"; then
    sed -i "s|$old|$new|g" "$file" || die "Failed changing: $label"
    log "Changed: $label"
  elif grep -Fq "$new" "$file"; then
    log "Already applied: $label"
  else
    log "WARNING: Expected string not found for: $label"
    log "WARNING: File may be newer, customized, or already changed differently: $file"
  fi
}

apply_responsive(){
  need_root

  require_file "$INDEX_FILE"
  require_file "$CSS_FILE"
  require_file "$LH_FILE"
  require_file "$LOCALTX_FILE"
  require_file "$SYSTEM_FILE"

  ensure_original_backup
  create_run_backup

  log "Applying DVSwitch Dashboard display layout tweaks v$VERSION"

  replace_or_confirm "$INDEX_FILE" '<td valign="top" style="border:none; height: 480px; background-color:#fafafa;">' '<td valign="top" style="border:none; height: 480px; background-color:#fafafa; width:100%;">' "index.php main content td width 100%"

  replace_or_confirm "$CSS_FILE" "width: 900px;" "width: min(96vw, 1200px);" "css.php container width 900px -> min(96vw, 1200px)"
  log "Preserved stock nav width: width : 185px; (no responsive nav-width patch applied)"
  replace_or_confirm "$CSS_FILE" "white-space: nowrap;" "white-space: normal;" "css.php table white-space nowrap -> normal"

  replace_or_confirm "$LH_FILE" "width:640px;" "width:min(95%,1400px);" "lh.php Gateway Activity fieldset width 640px -> min(95%,1400px)"
  replace_or_confirm "$LOCALTX_FILE" "width:640px;" "width:min(95%,1400px);" "localtx.php Local Activity fieldset width 640px -> min(95%,1400px)"

  replace_or_confirm "$SYSTEM_FILE" "width:855px" "width:min(95%,1400px)" "system.php Hardware Info width 855px -> min(95%,1400px)"
  replace_or_confirm "$SYSTEM_FILE" "margin-left:6px;margin-right:0px" "margin-left:auto;margin-right:auto" "system.php Hardware Info margin center"

  log "Responsive dashboard tweaks complete."
  log "Protected original backup: $ORIGINAL_BACKUP_DIR"
  log "Per-run backup: $RUN_BACKUP_DIR"
  log "Refresh the DVSwitch Dashboard in the browser."
  log "Log file: $LOG_FILE"
}

restore_latest_run_backup(){
  need_root

  latest="$(find "$ROOT" -maxdepth 1 -type d -name '.dvs-dashboard-display-backup-*' | sort | tail -n 1)"
  [ -n "$latest" ] || die "No per-run display dashboard backup directory found in $ROOT"

  restore_dashboard_files_from "$latest"

  log "Restored dashboard files from latest per-run backup: $latest"
  log "Protected original backup was not changed: $ORIGINAL_BACKUP_DIR"
  log "Log file: $LOG_FILE"
}

restore_original_backup(){
  need_root

  [ -d "$ORIGINAL_BACKUP_DIR" ] || die "Protected original backup does not exist: $ORIGINAL_BACKUP_DIR"

  restore_dashboard_files_from "$ORIGINAL_BACKUP_DIR"

  log "Restored dashboard files from protected original backup: $ORIGINAL_BACKUP_DIR"
  log "This should return the dashboard files to their pre-display-patch state."
  log "Log file: $LOG_FILE"
}

show_status(){
  echo "DVSwitch Dashboard Display Layout v$VERSION"
  echo
  echo "Tracked files:"
  echo "  $INDEX_FILE"
  echo "  $CSS_FILE"
  echo "  $LH_FILE"
  echo "  $LOCALTX_FILE"
  echo "  $SYSTEM_FILE"
  echo
  if [ -d "$ORIGINAL_BACKUP_DIR" ]; then
    echo "Protected original backup: FOUND"
    echo "  $ORIGINAL_BACKUP_DIR"
  else
    echo "Protected original backup: NOT FOUND"
  fi
  echo
  echo "Current responsive markers:"
  grep -Hn 'width:100%;\|width: min(96vw, 1200px);\|white-space: normal;\|width:min(95%,1400px)\|margin-left:auto;margin-right:auto' "$INDEX_FILE" "$CSS_FILE" "$LH_FILE" "$LOCALTX_FILE" "$SYSTEM_FILE" 2>/dev/null || true
}

case "${1:-menu}" in
  apply)
    apply_responsive
    ;;
  restore-latest)
    restore_latest_run_backup
    ;;
  restore-original|restore-factory)
    restore_original_backup
    ;;
  status)
    show_status
    ;;
  *)
    echo "DVSwitch Dashboard Display Layout v$VERSION"
    echo "1 = Apply dispaly layout tweaks"
    echo "2 = Restore latest per-run backup"
    echo "3 = Restore protected original files"
    echo "4 = Show display-layout status markers"
    echo "0 = Exit"
    printf "Choose an action [0/1/2/3/4]: "
    read -r choice
    case "$choice" in
      1) apply_responsive ;;
      2) restore_latest_run_backup ;;
      3) restore_original_backup ;;
      4) show_status ;;
      0) exit 0 ;;
      *) die "Invalid choice" ;;
    esac
    ;;
esac
