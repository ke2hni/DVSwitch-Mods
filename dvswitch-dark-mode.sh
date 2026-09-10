#!/usr/bin/env bash
set -u

VERSION="1.0"
ROOT="/usr/share/dvswitch"
ORIGINAL_BACKUP_DIR="$ROOT/.dvs-dashboard-original-backup"
CSS_FILE="$ROOT/css/dvs-theme.css"
JS_FILE="$ROOT/scripts/dvs-theme.js"
INDEX_FILE="$ROOT/index.php"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$ROOT/.dvs-dashboard-theme-backup-$STAMP"
LOG_FILE="$HOME/dvs-dashboard-theme-$STAMP.log"

log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
die(){ log "ERROR: $*"; exit 1; }

need_root(){
  if [ "$(id -u)" -ne 0 ]; then
    die "Run with sudo."
  fi
}

dashboard_files(){
  printf '%s\n' "index.php"
}

copy_dashboard_file_set(){
  src_root="$1"
  dst_root="$2"

  dashboard_files | while IFS= read -r rel; do
    [ -f "$src_root/$rel" ] || die "Missing source file: $src_root/$rel"
    mkdir -p "$dst_root/$(dirname "$rel")" || die "Could not create destination path: $dst_root/$(dirname "$rel")"
    cp -a "$src_root/$rel" "$dst_root/$rel" || die "Could not copy $rel"
  done
}

create_original_backup_once(){
  if [ -d "$ORIGINAL_BACKUP_DIR" ]; then
    log "Original factory backup already exists and will NOT be overwritten: $ORIGINAL_BACKUP_DIR"
    return 0
  fi

  mkdir -p "$ORIGINAL_BACKUP_DIR" || die "Could not create original backup dir"
  copy_dashboard_file_set "$ROOT" "$ORIGINAL_BACKUP_DIR"

  {
    echo "DVSwitch Dashboard original factory backup"
    echo "Created: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Script: DVSwitch Dashboard Theme Overlay v$VERSION"
    echo "Source: $ROOT"
    echo
    echo "This directory is intentionally created once and must not be overwritten."
  } > "$ORIGINAL_BACKUP_DIR/README.original-backup.txt"

  log "Created protected original factory backup: $ORIGINAL_BACKUP_DIR"
}

create_run_backup(){
  mkdir -p "$BACKUP_DIR" || die "Could not create run backup dir"
  copy_dashboard_file_set "$ROOT" "$BACKUP_DIR"

  mkdir -p "$BACKUP_DIR/css" "$BACKUP_DIR/scripts" || die "Could not create theme backup paths"
  [ -f "$CSS_FILE" ] && cp -a "$CSS_FILE" "$BACKUP_DIR/css/dvs-theme.css"
  [ -f "$JS_FILE" ] && cp -a "$JS_FILE" "$BACKUP_DIR/scripts/dvs-theme.js"

  {
    echo "DVSwitch Dashboard run backup"
    echo "Created: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Script: DVSwitch Dashboard Theme Overlay v$VERSION"
    echo "Source: $ROOT"
  } > "$BACKUP_DIR/README.run-backup.txt"

  log "Created run backup: $BACKUP_DIR"
}

write_theme_files(){
  cat > "$CSS_FILE" <<'CSS'
/*
 * DVSwitch Dashboard Theme Overlay
 * v0.25-test
 *
 * Modes:
 *   Auto  = follows browser/system prefers-color-scheme
 *   Light = stock/light dashboard
 *   Dark  = forced dark dashboard
 *
 * Important:
 *   Do not globally recolor every td cell.
 *   DVSwitch uses inline green/red/orange cells for live status.
 */

.dvs-theme-control {
  position: absolute;
  top: 8px;
  right: 12px;
  z-index: 20;
  font: 12px arial, sans-serif;
  color: #333333;
  background: rgba(255,255,255,0.86);
  border: 1px solid #cccccc;
  border-radius: 8px;
  padding: 5px 8px;
  box-shadow: 0 2px 5px rgba(0,0,0,0.16);
}

.dvs-theme-control label {
  font-weight: bold;
  margin-right: 4px;
}

.dvs-theme-control select {
  font: 12px arial, sans-serif;
  border-radius: 5px;
  border: 1px solid #aaaaaa;
  padding: 2px 4px;
  background: #ffffff;
  color: #222222;
}

body.theme-dark,
body.theme-auto.dvs-prefers-dark {
  background-color: #111827 !important;
  color: #e5e7eb !important;
}

/* Keep the left status/nav column matched to the main content background. */
body.theme-dark .nav,
body.theme-auto.dvs-prefers-dark .nav,
body.theme-dark #modeInfo,
body.theme-auto.dvs-prefers-dark #modeInfo,
body.theme-dark td.hide,
body.theme-auto.dvs-prefers-dark td.hide,
body.theme-dark td[width="200px"],
body.theme-auto.dvs-prefers-dark td[width="200px"],
body.theme-dark td[style*="width=200px"],
body.theme-auto.dvs-prefers-dark td[style*="width=200px"] {
  background: #111827 !important;
  background-color: #111827 !important;
  color: #e5e7eb !important;
}

body.theme-dark td.hide *,
body.theme-auto.dvs-prefers-dark td.hide *,
body.theme-dark #modeInfo *,
body.theme-auto.dvs-prefers-dark #modeInfo * {
  border-color: #374151 !important;
}

/* Center only the confirmed loose Status label in include/status.php line 7. */
body.theme-light #modeInfo > span,
body.theme-dark #modeInfo > span,
body.theme-auto #modeInfo > span,
body.theme-auto.dvs-prefers-dark #modeInfo > span {
  display: inline-block !important;
  width: 180px !important;
  text-align: center !important;
  background: transparent !important;
  margin: 0 0 0 0 !important;
  padding: 0 !important;
}

body.theme-dark #modeInfo > span,
body.theme-auto.dvs-prefers-dark #modeInfo > span {
  color: #e5e7eb !important;
}

/* Keep the Status label inline; do not add extra spacing. */
body.theme-dark #modeInfo > span,
body.theme-auto.dvs-prefers-dark #modeInfo > span {
  background: transparent !important;
  background-color: transparent !important;
  color: #e5e7eb !important;
}

/* Keep the page/content background dark so boxes look independent/floating. */
body.theme-dark .content,
body.theme-auto.dvs-prefers-dark .content,
body.theme-dark .content2,
body.theme-auto.dvs-prefers-dark .content2,
body.theme-dark td[style*="height: 480px"],
body.theme-auto.dvs-prefers-dark td[style*="height: 480px"] {
  background-color: #111827 !important;
  color: #e5e7eb !important;
}

/* Keep actual dashboard panels slightly lighter so they float above the background. */
body.theme-dark .container,
body.theme-auto.dvs-prefers-dark .container,
body.theme-dark fieldset,
body.theme-auto.dvs-prefers-dark fieldset {
  background-color: #1f2937 !important;
  color: #e5e7eb !important;
  border-color: #4b5563 !important;
  box-shadow: 0 0 10px rgba(229,231,235,0.35) !important;
}

body.theme-dark legend,
body.theme-auto.dvs-prefers-dark legend {
  background-color: #1f2937 !important;
  color: #e5e7eb !important;
  border-color: #4b5563 !important;
}

/* Only replace known light dashboard table/panel backgrounds. */
body.theme-dark table[style*="background-color:#fafafa"],
body.theme-auto.dvs-prefers-dark table[style*="background-color:#fafafa"],
body.theme-dark tr[style*="background-color:#fafafa"],
body.theme-auto.dvs-prefers-dark tr[style*="background-color:#fafafa"],
body.theme-dark td[style*="background-color:#fafafa"],
body.theme-auto.dvs-prefers-dark td[style*="background-color:#fafafa"],
body.theme-dark td[style*="background-color:#f9f9f9"],
body.theme-auto.dvs-prefers-dark td[style*="background-color:#f9f9f9"],
body.theme-dark td[style*="background: #f9f9f9"],
body.theme-auto.dvs-prefers-dark td[style*="background: #f9f9f9"],
body.theme-dark td[style*="background:#f9f9f9"],
body.theme-auto.dvs-prefers-dark td[style*="background:#f9f9f9"],
body.theme-dark td[style*="background: #ffffff"],
body.theme-auto.dvs-prefers-dark td[style*="background: #ffffff"],
body.theme-dark td[style*="background:#ffffff"],
body.theme-auto.dvs-prefers-dark td[style*="background:#ffffff"],
body.theme-dark td[style*="background: #ffffed"],
body.theme-auto.dvs-prefers-dark td[style*="background: #ffffed"],
body.theme-dark td[style*="background:#ffffed"],
body.theme-auto.dvs-prefers-dark td[style*="background:#ffffed"] {
  background-color: #111827 !important;
  color: #e5e7eb !important;
  border-color: #374151 !important;
}

body.theme-dark th,
body.theme-auto.dvs-prefers-dark th {
  background-color: #111827 !important;
  color: #f9fafb !important;
  border-color: #374151 !important;
}

body.theme-dark table,
body.theme-auto.dvs-prefers-dark table,
body.theme-dark tr,
body.theme-auto.dvs-prefers-dark tr,
body.theme-dark td,
body.theme-auto.dvs-prefers-dark td {
  border-color: #374151 !important;
}


/* Gateway Activity live table only.
 * index.php refreshes include/lh.php into #lastHerd every 1.5 seconds.
 * Target #lastHerd directly so newly received RX rows keep the dark two-tone
 * style after AJAX refresh. Exclude inline background cells so RX/TX, LNet,
 * Loss, BER, and other live semantic colors remain untouched.
 */
body.theme-dark #lastHerd fieldset table tr:nth-child(odd) td:not([style*="background"]),
body.theme-auto.dvs-prefers-dark #lastHerd fieldset table tr:nth-child(odd) td:not([style*="background"]) {
  background-color: #111827 !important;
  color: #e5e7eb !important;
  border-color: #374151 !important;
}

body.theme-dark #lastHerd fieldset table tr:nth-child(even) td:not([style*="background"]),
body.theme-auto.dvs-prefers-dark #lastHerd fieldset table tr:nth-child(even) td:not([style*="background"]) {
  background-color: #1f2937 !important;
  color: #e5e7eb !important;
  border-color: #374151 !important;
}

/* Gateway Activity uses inline dark-gray text in normal cells. Lighten only
 * those normal cells inside #lastHerd; do not alter inline background status cells.
 */
body.theme-dark #lastHerd fieldset table td:not([style*="background"]) span[style*="color:#464646"],
body.theme-auto.dvs-prefers-dark #lastHerd fieldset table td:not([style*="background"]) span[style*="color:#464646"],
body.theme-dark #lastHerd fieldset table td[style*="color:#464646"],
body.theme-auto.dvs-prefers-dark #lastHerd fieldset table td[style*="color:#464646"] {
  color: #d1d5db !important;
}




/* Local Activity live table only.
 * index.php refreshes include/localtx.php into #localTxs every 1.5 seconds.
 * Match the confirmed Gateway Activity two-tone dark treatment, scoped only
 * to #localTxs. Exclude inline background cells so LNet, TX, DMR Data,
 * and other live semantic colors remain untouched.
 */
body.theme-dark #localTxs fieldset table tr:nth-child(odd) td:not([style*="background"]),
body.theme-auto.dvs-prefers-dark #localTxs fieldset table tr:nth-child(odd) td:not([style*="background"]) {
  background-color: #111827 !important;
  color: #e5e7eb !important;
  border-color: #374151 !important;
}

body.theme-dark #localTxs fieldset table tr:nth-child(even) td:not([style*="background"]),
body.theme-auto.dvs-prefers-dark #localTxs fieldset table tr:nth-child(even) td:not([style*="background"]) {
  background-color: #1f2937 !important;
  color: #e5e7eb !important;
  border-color: #374151 !important;
}

/* Local Activity also uses inline dark-gray text in normal cells. Lighten only
 * those normal cells inside #localTxs; do not alter inline background cells.
 */
body.theme-dark #localTxs fieldset table td:not([style*="background"]) span[style*="color:#464646"],
body.theme-auto.dvs-prefers-dark #localTxs fieldset table td:not([style*="background"]) span[style*="color:#464646"],
body.theme-dark #localTxs fieldset table td[style*="color:#464646"],
body.theme-auto.dvs-prefers-dark #localTxs fieldset table td[style*="color:#464646"] {
  color: #d1d5db !important;
}

/* Hardware Info value row only.
 * Target the second dashboard fieldset in include/system.php and only its
 * value row. Exclude cells with inline background so CPU Temp keeps its
 * green/orange/red threshold color.
 */
body.theme-dark fieldset:nth-of-type(2) table tr[height="24px"] td:not([style*="background"]),
body.theme-auto.dvs-prefers-dark fieldset:nth-of-type(2) table tr[height="24px"] td:not([style*="background"]) {
  background-color: #111827 !important;
  color: #e5e7eb !important;
  border-color: #374151 !important;
}

/* Preserve live semantic colors/status cells. */
body.theme-dark td[style*="background:#0b0"],
body.theme-auto.dvs-prefers-dark td[style*="background:#0b0"],
body.theme-dark td[style*="background:#12AD2A"],
body.theme-auto.dvs-prefers-dark td[style*="background:#12AD2A"] {
  background-color: #12AD2A !important;
  color: #030 !important;
}

body.theme-dark td[style*="background:#b00"],
body.theme-auto.dvs-prefers-dark td[style*="background:#b00"],
body.theme-dark td[style*="background:#f33"],
body.theme-auto.dvs-prefers-dark td[style*="background:#f33"] {
  background-color: #b00 !important;
  color: #f9f9f9 !important;
}

body.theme-dark td[style*="background:#606060"],
body.theme-auto.dvs-prefers-dark td[style*="background:#606060"] {
  background-color: #606060 !important;
  color: #b0b0b0 !important;
}

body.theme-dark a,
body.theme-auto.dvs-prefers-dark a {
  color: #93c5fd !important;
}

body.theme-dark h1,
body.theme-auto.dvs-prefers-dark h1,
body.theme-dark h2,
body.theme-auto.dvs-prefers-dark h2,
body.theme-dark h3,
body.theme-auto.dvs-prefers-dark h3 {
  color: #f9fafb;
}

body.theme-dark .dvs-theme-control,
body.theme-auto.dvs-prefers-dark .dvs-theme-control {
  background: rgba(17,24,39,0.94);
  color: #e5e7eb;
  border-color: #4b5563;
}

body.theme-dark .dvs-theme-control select,
body.theme-auto.dvs-prefers-dark .dvs-theme-control select {
  background: #111827;
  color: #e5e7eb;
  border-color: #4b5563;
}

body.theme-dark input[type=text],
body.theme-auto.dvs-prefers-dark input[type=text],
body.theme-dark .dropdown-content,
body.theme-auto.dvs-prefers-dark .dropdown-content {
  background-color: #111827 !important;
  color: #e5e7eb !important;
  border-color: #4b5563 !important;
}

body.theme-dark .dropdown-content a,
body.theme-auto.dvs-prefers-dark .dropdown-content a {
  color: #e5e7eb !important;
}

body.theme-dark .dropdown-content a:hover,
body.theme-auto.dvs-prefers-dark .dropdown-content a:hover {
  background-color: #374151 !important;
}

body.theme-dark .dropbtn,
body.theme-auto.dvs-prefers-dark .dropbtn {
  background-color: #2563eb !important;
  color: #ffffff !important;
}

body.theme-dark .dropbtn:hover,
body.theme-auto.dvs-prefers-dark .dropbtn:hover {
  background-color: #1d4ed8 !important;
}
CSS

  cat > "$JS_FILE" <<'JS'
(function () {
  var key = "dvsTheme";

  function prefersDark() {
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  }

  function applyTheme(mode) {
    var body = document.body;
    if (!body) return;

    mode = mode || localStorage.getItem(key) || "auto";
    if (["auto", "light", "dark"].indexOf(mode) === -1) mode = "auto";

    body.classList.remove("theme-auto", "theme-light", "theme-dark", "dvs-prefers-dark");
    body.classList.add("theme-" + mode);

    if (mode === "auto" && prefersDark()) {
      body.classList.add("dvs-prefers-dark");
    }

    var select = document.getElementById("dvs-theme-select");
    if (select) select.value = mode;
  }

  function buildControl() {
    if (document.getElementById("dvs-theme-control")) return;

    var header = document.querySelector(".header");
    if (!header) return;

    header.style.position = header.style.position || "relative";

    var wrap = document.createElement("div");
    wrap.id = "dvs-theme-control";
    wrap.className = "dvs-theme-control";

    var label = document.createElement("label");
    label.setAttribute("for", "dvs-theme-select");
    label.appendChild(document.createTextNode("Theme:"));

    var select = document.createElement("select");
    select.id = "dvs-theme-select";

    [
      ["auto", "Auto"],
      ["light", "Light"],
      ["dark", "Dark"]
    ].forEach(function (item) {
      var opt = document.createElement("option");
      opt.value = item[0];
      opt.appendChild(document.createTextNode(item[1]));
      select.appendChild(opt);
    });

    select.addEventListener("change", function () {
      localStorage.setItem(key, select.value);
      applyTheme(select.value);
    });

    wrap.appendChild(label);
    wrap.appendChild(select);
    header.appendChild(wrap);
    applyTheme(localStorage.getItem(key) || "auto");
  }

  document.addEventListener("DOMContentLoaded", function () {
    applyTheme(localStorage.getItem(key) || "auto");
    buildControl();

    if (window.matchMedia) {
      var mq = window.matchMedia("(prefers-color-scheme: dark)");
      var handler = function () {
        if ((localStorage.getItem(key) || "auto") === "auto") {
          applyTheme("auto");
        }
      };

      if (mq.addEventListener) mq.addEventListener("change", handler);
      else if (mq.addListener) mq.addListener(handler);
    }
  });
})();
JS
}

apply_theme(){
  need_root
  [ -f "$INDEX_FILE" ] || die "Missing $INDEX_FILE"
  [ -d "$ROOT/css" ] || die "Missing $ROOT/css"
  [ -d "$ROOT/scripts" ] || die "Missing $ROOT/scripts"

  create_original_backup_once
  create_run_backup

  write_theme_files

  if ! grep -q 'css/dvs-theme.css' "$INDEX_FILE"; then
    sed -i '/<link href="css\/featherlight.css" type="text\/css" rel="stylesheet" \/>/i <link href="css/dvs-theme.css" type="text/css" rel="stylesheet" />' "$INDEX_FILE" || die "Could not add theme CSS include"
    log "Added theme CSS include to index.php"
  else
    log "Theme CSS include already present"
  fi

  if ! grep -q 'scripts/dvs-theme.js' "$INDEX_FILE"; then
    sed -i '/<script src="scripts\/featherlight.js" type="text\/javascript" charset="utf-8"><\/script>/a \    <script src="scripts/dvs-theme.js" type="text/javascript"></script>' "$INDEX_FILE" || die "Could not add theme JS include"
    log "Added theme JS include to index.php"
  else
    log "Theme JS include already present"
  fi

  log "Applied DVSwitch dashboard theme overlay v$VERSION"
  log "Backup directory: $BACKUP_DIR"
  log "Log file: $LOG_FILE"
  log "Refresh the dashboard, then use Theme: Auto / Light / Dark in the header."
}

restore_latest(){
  need_root
  latest="$(find "$ROOT" -maxdepth 1 -type d -name '.dvs-dashboard-theme-backup-*' | sort | tail -n 1)"
  [ -n "$latest" ] || die "No dashboard run backup directory found in $ROOT"

  copy_dashboard_file_set "$latest" "$ROOT"

  if [ -f "$latest/css/dvs-theme.css" ]; then
    cp -a "$latest/css/dvs-theme.css" "$CSS_FILE" || die "Could not restore previous dvs-theme.css"
  else
    rm -f "$CSS_FILE"
  fi

  if [ -f "$latest/scripts/dvs-theme.js" ]; then
    cp -a "$latest/scripts/dvs-theme.js" "$JS_FILE" || die "Could not restore previous dvs-theme.js"
  else
    rm -f "$JS_FILE"
  fi

  log "Restored latest dashboard run backup from: $latest"
  log "Original factory backup was NOT changed: $ORIGINAL_BACKUP_DIR"
  log "Log file: $LOG_FILE"
}

restore_original(){
  need_root
  [ -d "$ORIGINAL_BACKUP_DIR" ] || die "No original factory backup found at $ORIGINAL_BACKUP_DIR"
  [ -f "$ORIGINAL_BACKUP_DIR/index.php" ] || die "Original backup is missing index.php"

  mkdir -p "$BACKUP_DIR" || die "Could not create pre-restore run backup dir"
  copy_dashboard_file_set "$ROOT" "$BACKUP_DIR"
  mkdir -p "$BACKUP_DIR/css" "$BACKUP_DIR/scripts" || die "Could not create pre-restore theme backup paths"
  [ -f "$CSS_FILE" ] && cp -a "$CSS_FILE" "$BACKUP_DIR/css/dvs-theme.css"
  [ -f "$JS_FILE" ] && cp -a "$JS_FILE" "$BACKUP_DIR/scripts/dvs-theme.js"
  log "Created safety backup before factory restore: $BACKUP_DIR"

  copy_dashboard_file_set "$ORIGINAL_BACKUP_DIR" "$ROOT"
  rm -f "$CSS_FILE" "$JS_FILE"

  log "Restored original factory dashboard files from: $ORIGINAL_BACKUP_DIR"
  log "Removed theme overlay files: $CSS_FILE and $JS_FILE"
  log "Log file: $LOG_FILE"
}

case "${1:-menu}" in
  apply) apply_theme ;;
  restore-latest) restore_latest ;;
  restore-original) restore_original ;;
  *)
    echo "DVSwitch Dashboard Theme Overlay v$VERSION"
    echo "1 = Apply Auto/Light/Dark theme toggle"
    echo "2 = Restore latest run backup"
    echo "3 = Restore original factory dashboard files"
    echo "0 = Exit"
    printf "Choose an action [0/1/2/3]: "
    read -r choice
    case "$choice" in
      1) apply_theme ;;
      2) restore_latest ;;
      3) restore_original ;;
      0) exit 0 ;;
      *) die "Invalid choice" ;;
    esac
    ;;
esac