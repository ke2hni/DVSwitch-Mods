#!/usr/bin/env python3
"""Static regression checks for CTY.DAT fallback integration."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
helper = (ROOT / "lib/dvswitch_mods_fcc_first_names.php").read_text()
patcher = (ROOT / "lib/patch_dashboard_first_names.py").read_text()
updater = (ROOT / "lib/dvswitch_fcc_first_names_update.sh").read_text()
timer = (ROOT / "systemd/dvswitch-fcc-first-names-update.timer").read_text()

checks = {
    "database is colocated under /var/lib/mmdvm": "/var/lib/mmdvm/dvswitch-mods-cty.dat" in helper and "/var/lib/mmdvm/dvswitch-mods-cty.dat" in updater,
    "country only appears when no DMR/FCC name exists": "$dvsModsFirstName === '---'" in patcher,
    "entity is rendered on a separate escaped line": "$dvsModsNameHtml .= '<br>'.htmlspecialchars($dvsModsCountry" in patcher,
    "download is bounded and validated before replacement": "--max-time 120" in updater and "validate_cty \"$cty_archive\"" in updater,
    "failed feed retains last known good copy": "keeping the last known good file" in updater,
    "country feed refresh is weekly": "OnCalendar=Mon *-*-* 00:00:00" in timer,
}

failed = [name for name, passed in checks.items() if not passed]
if failed:
    raise SystemExit("FAIL: " + "; ".join(failed))
print("PASS: CTY.DAT fallback and updater integration checks")
