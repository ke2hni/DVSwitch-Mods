#!/usr/bin/env python3
# Version: 1.0.0
"""Static regression checks for CTY.DAT fallback integration."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
helper = (ROOT / "lib/dvswitch_mods_fcc_first_names.php").read_text()
patcher = (ROOT / "lib/patch_dashboard_first_names.py").read_text()
updater = (ROOT / "lib/dvswitch_fcc_first_names_update.sh").read_text()
installer = (ROOT / "mod-dashboard-fcc-first-names.sh").read_text()
timer = (ROOT / "systemd/dvswitch-fcc-first-names-update.timer").read_text()

checks = {
    "database is colocated under /var/lib/mmdvm": "/var/lib/mmdvm/dvswitch-mods-cty.dat" in helper and "/var/lib/mmdvm/dvswitch-mods-cty.dat" in updater,
    "country only appears when no DMR/FCC name or custom description exists": "$dvsModsFirstName === '---'" in patcher,
    "custom callsign lookup precedes country fallback": "dvsModsCustomCallsignDescription($listElem[2])" in patcher and "dvsModsFccCountry($listElem[2])" in patcher,
    "custom callsign data is user-editable outside the repository": "'/etc/dvswitch-mods/callsign-descriptions.tsv'" in helper,
    "entity is rendered on a separate escaped line": "$dvsModsNameHtml .= '<br>'.htmlspecialchars($dvsModsCountry" in patcher,
    "download is bounded and validated before replacement": "--max-time 120" in updater and "validate_cty \"$cty_archive\"" in updater,
    "failed feed retains last known good copy": "keeping the last known good file" in updater,
    "country feed refresh is weekly": "OnCalendar=Mon *-*-* 00:00:00" in timer,
    "installer requires initial CTY.DAT before installation": 'readonly CTY_DATABASE_TARGET="/var/lib/mmdvm/dvswitch-mods-cty.dat"' in installer and 'readonly CTY_URL="https://www.country-files.com/cty/cty.dat"' in installer and 'prepare_cty_candidate' in installer and 'CTY.DAT download or validation failed. No installation changes have been made' in installer,
    "installer CTY download is bounded and validated": '--max-time 120 --retry 2 --output "$archive" "$CTY_URL"' in installer and 'validate_cty "$archive"' in installer,
    "installer includes CTY in reversible transaction": 'stage_install_component "$WORK_DIR/cty.dat" "$CTY_DATABASE_TARGET" root www-data 0644' in installer and '"$DATABASE_TARGET" "$CTY_DATABASE_TARGET"' in installer,
    "installer avoids CTY fetch when existing data is valid": 'if validate_cty "$CTY_DATABASE_TARGET"; then cty_ready=1; fi' in installer,
    "install validates CTY before reporting success": 'validate_cty "$CTY_DATABASE_TARGET" || die "Installed CTY.DAT failed validation."' in installer,
}

failed = [name for name, passed in checks.items() if not passed]
if failed:
    raise SystemExit("FAIL: " + "; ".join(failed))
print("PASS: CTY.DAT fallback and updater integration checks")
