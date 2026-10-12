#!/usr/bin/env python3
# Version: 1.0.0
"""Regression tests for surgical FCC Gateway Activity patching."""
from __future__ import annotations

import importlib.util
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPDATER = ROOT / "lib/dvswitch_fcc_first_names_update.sh"
spec = importlib.util.spec_from_file_location("patcher", ROOT / "lib/patch_dashboard_first_names.py")
patcher = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(patcher)

def require(value: bool, message: str) -> None:
    if not value:
        raise SystemExit("FAIL: " + message)

updater_text = UPDATER.read_text(encoding="utf-8")
require("_SHA256=" not in updater_text and "checksum is unsupported" not in updater_text,
        "FCC updater still contains a release-pinned SHA checksum gate")
for required in ("python3 \"$BUILDER\" --help", "python3 \"$PATCHER\" --help", "bash -n \"$TRANSACTION_LIBRARY\"", "cmp -s \"$candidate\" \"$DATABASE_TARGET\""):
    require(required in updater_text, "FCC updater structural validation is missing: " + required)

fixture = '''<?php
include_once dirname(dirname(__FILE__)).'/include/functions.php';FUNCTIONS_ANCHOR
      <th>Time (<?php echo date('T')?>)</th>
      <th>Callsign</th>
<?php
    if (DISPLAYNAME == "YES" && file_exists(DMRIDDATPATH."/DMRIds.dat") && ! empty(DMRIDDATPATH."/DMRIds.dat")) { echo "<th>Name</th>"; }
?>
        if ((is_numeric($listElem[2]) || strpos($listElem[2], "openSPOT") !== FALSE) && (strlen($listElem[2])==7)) {
// Display NAME by DV8AWC
        if ( DISPLAYNAME == "YES" ) {
        }
        if (strlen($listElem[4]) == 1) { $listElem[4] = str_pad($listElem[4], 8, " ", STR_PAD_LEFT); }
'''.replace("FUNCTIONS_ANCHOR", "    ")

changed = patcher.patch_text(fixture)
require(changed.count(patcher.MARKER) == 1, "marker missing")
require(changed.count(patcher.INCLUDE) == 1, "helper include missing")
require(changed.count("dvsModsFccFirstName($listElem[2])") == 1, "FCC lookup missing")
require(changed.count("dvsModsCustomCallsignDescription($listElem[2])") == 1, "custom description lookup missing")
require(changed.index("$dvsModsFirstName = dvsModsFccFirstName") < changed.index("dvsModsManualCallsignName($listElem[2])") < changed.index("dvsModsCustomCallsignDescription($listElem[2])"), "FCC/DMR database name does not take precedence over manual and custom fallback names")
require("$dvsModsNameHtml = '<button type=\"button\"" in changed and "fetch(&#39;callsign-lookup.php&#39;" in changed and "&#39;data-callsign&#39;" in changed, "unknown name marker is not clickable with a local save action")
require(patcher.MARKER.endswith("v3"), "FCC patch version was not advanced for manual names")
require(changed.count("dvsModsDmrIdCallsign($listElem[2])") == 1, "DMR resolver missing")
require(changed.count("width:12ch;min-width:12ch;max-width:12ch") == 1, "Name-cell width and wrap limit missing")
require(changed.count("overflow-wrap:anywhere") == 1, "Name-cell overflow wrapping missing")
require("width:640px" not in changed, "fixture unexpectedly contained layout width")
require(patcher.patch_text(changed) == changed, "patch is not idempotent")
legacy_country_upgrade = changed.replace(patcher.NAME_BLOCK, patcher.OLD_NAME_BLOCK, 1).replace(patcher.MARKER, patcher.PREVIOUS_MARKER, 1)
require(legacy_country_upgrade != changed, "failed to prepare legacy country-fallback fixture")
require(patcher.patch_text(legacy_country_upgrade) == changed, "existing country-fallback installation was not upgraded")

legacy_name_style = changed.replace(patcher.NAME_CELL_STYLE_NEW, patcher.NAME_CELL_STYLE_OLD, 1)
require(patcher.patch_text(legacy_name_style) == changed, "installed FCC Name-cell style was not upgraded")

legacy_width_style = changed.replace(patcher.NAME_CELL_STYLE_NEW, patcher.NAME_CELL_STYLE_LEGACY_WIDTH, 1)
require(patcher.patch_text(legacy_width_style) == changed, "installed 10ch FCC Name-cell style was not upgraded")

legacy = changed.replace(patcher.MARKER, patcher.LEGACY_MARKER, 1)
require(patcher.patch_text(legacy) == changed, "legacy marker was not upgraded")

legacy_name = changed.replace(patcher.NAME_BLOCK, patcher.OLD_LEGACY_NAME, 1)
legacy_name = legacy_name.replace("$dvsModsNameHtml.'</b></td>';", "htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, \"UTF-8\").'</b></td>';", 1)
legacy_name = legacy_name.replace(patcher.MARKER, patcher.LEGACY_MARKER, 1)
require(patcher.patch_text(legacy_name) == changed, "legacy FCC Name block was not upgraded")

targeted = changed.replace(
    "if (strlen($listElem[4]) == 1)",
    "$dvsModsTarget = dvsModsTargetDisplay($listElem[1], $listElem[4], $listElem[6]);\n\t\techo 'target';\n        if (strlen($listElem[4]) == 1)",
    1,
)
require(patcher.patch_text(targeted) == targeted, "FCC altered Target-installed Gateway Activity")

try:
    patcher.patch_text(fixture.replace("// Display NAME by DV8AWC", "// Display NAME by DV8AWC\n// Display NAME by DV8AWC"))
except patcher.PatchError:
    pass
else:
    raise SystemExit("FAIL: ambiguous FCC name block accepted")

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "lh.php"
    path.write_bytes(fixture.replace("\n", "\r\n").encode())
    localtx = Path(directory) / "localtx.php"
    localtx.write_text('<div><b>Legend:</b> <b>---</b> = no data</div>', encoding="utf-8")
    subprocess.run(["python3", str(ROOT / "lib/patch_dashboard_first_names.py"), "--lh", str(path), "--localtx", str(localtx)], check=True)
    raw = path.read_bytes()
    require(b"\r\n" in raw and b"\n" not in raw.replace(b"\r\n", b""), "CRLF was not preserved")
    legend = localtx.read_text(encoding="utf-8")
    require(patcher.LEGEND_MARKER in legend and "/etc/dvswitch-mods/callsign-lookup.tsv" in legend, "manual callsign legend was not added")
    require("Name entered manually and saved in the local callsign names file" in legend and ">file location</span>" in legend,
            "manual callsign legend does not explain the marker and file path")
    require(legend.count("width:3ch;text-align:right") == 2, "equals signs do not align across the --- and * legend rows")
    require(patcher.patch_legend_text(legend) == legend, "aligned legend patch is not idempotent")

legacy_legend = ('<div><b>Legend:</b> <b>---</b> = no data<br>\n  <b>*</b> = Name entered and saved by you in the local callsign file. '
                 '<span title="Manually entered callsign names are stored in /etc/dvswitch-mods/callsign-lookup.tsv.">Database</span>\n  '
                 '<!-- DVSwitch-Mods: manual callsign names legend v1 -->\n</div>')
upgraded_legend = patcher.patch_legend_text(legacy_legend)
require(patcher.LEGEND_MARKER in upgraded_legend and "manual callsign names legend v1" not in upgraded_legend,
        "existing manual callsign legend marker was not upgraded")
require(upgraded_legend.count("width:3ch;text-align:right") == 2,
        "existing legend --- and * terms were not aligned during upgrade")
require(patcher.patch_legend_text(upgraded_legend) == upgraded_legend,
        "upgraded existing legend is not idempotent")
styled_v2_legend = ('<div><b>Legend:</b> <b style="display:inline-block;width:3ch;text-align:right;">---</b> = no data<br>\n  '
                    '<b style="display:inline-block;width:3ch;text-align:right;">*</b> = Name entered and saved by you in the local callsign file. '
                    '<span title="Manually entered callsign names are stored in /etc/dvswitch-mods/callsign-lookup.tsv.">Database</span>\n  '
                    '<!-- DVSwitch-Mods: manual callsign names legend v2 -->\n</div>')
upgraded_v2_legend = patcher.patch_legend_text(styled_v2_legend)
require(patcher.LEGEND_MARKER in upgraded_v2_legend and '<b>---</b>' in upgraded_v2_legend
        and '<b>*</b>' in upgraded_v2_legend,
        "v2 legend did not upgrade while preserving Target-mod-compatible bold tags")
require(patcher.patch_legend_text(upgraded_v2_legend) == upgraded_v2_legend,
        "upgraded v2 legend is not idempotent")
wrapped_v3_legend = ('<div><b>Legend:</b> <span style="display:inline-block;width:3ch;text-align:right;"><b>---</b></span> = no data<br>\n  '
                     '<span style="display:inline-block;width:3ch;text-align:right;"><b>*</b></span> = Name entered and saved by you in the local callsign file. '
                     '<span title="Manually entered callsign names are stored in /etc/dvswitch-mods/callsign-lookup.tsv.">Database</span>\n  '
                     '<!-- DVSwitch-Mods: manual callsign names legend v3 -->\n</div>')
upgraded_v3_legend = patcher.patch_legend_text(wrapped_v3_legend)
require(patcher.LEGEND_MARKER in upgraded_v3_legend and '<b>Legend:</b><br>\n' in upgraded_v3_legend,
        "v3 legend heading was not moved above its aligned rows")
require("Name entered manually and saved in the local callsign names file" in upgraded_v3_legend,
        "v3 legend wording was not updated")
require(patcher.patch_legend_text(upgraded_v3_legend) == upgraded_v3_legend,
        "upgraded v3 legend is not idempotent")

installer = (ROOT / "mod-dashboard-fcc-first-names.sh").read_text()
require('cmp -s "$TRANSACTION_LIBRARY" "$TRANSACTION_TARGET" || die' not in installer,
        "FCC dashboard installer still blocks a structurally compatible transaction helper revision")
require('transaction_library_supported "$TRANSACTION_TARGET"' in installer,
        "FCC dashboard installer does not validate the installed transaction helper structurally")
custom_file = (ROOT / "data/callsign-descriptions.tsv").read_text()
for entry in ("9999 = Announcement", "H4MLNK = YSF Link", "N0CALL = Announcement", "AMERICALNK = America Link"):
    require(entry in custom_file, "starter custom-description entry missing: " + entry)
require('readonly CALLSIGN_DESCRIPTIONS_TARGET="/etc/dvswitch-mods/callsign-descriptions.tsv"' in installer, "custom file install path missing")
require('if [[ ! -e "$CALLSIGN_DESCRIPTIONS_TARGET" ]]; then' in installer, "installer does not preserve existing user descriptions")
require('cp -a -- "$CALLSIGN_DESCRIPTIONS_TARGET" "$custom_temporary"' in installer, "uninstall does not preserve a user's custom descriptions")
require('"$CALLSIGN_DESCRIPTIONS_TARGET" "$CALLSIGN_NAMES_TARGET"; do backup_target "$target"; done' in installer, "uninstall safety backup omits user TSV files")
require('Custom callsign descriptions: editable file present' in installer, "--check does not report custom file state")
require('readonly CALLSIGN_NAMES_TARGET="/etc/dvswitch-mods/callsign-lookup.tsv"' in installer, "manual callsign names file path missing")
require('readonly LOCALTX_TARGET="/usr/share/dvswitch/include/localtx.php"' in installer, "legend dashboard file target missing")
require('dvsModsSaveManualCallsignName($_POST[\'callsign\'] ?? \'\', $_POST[\'name\'] ?? \'\')' in (ROOT / "lib/dvswitch_mods_callsign_name_save.php").read_text(), "server-side manual name endpoint is missing")
require("--localtx" in installer, "FCC installer does not patch the legend")
require('require_file "$LH_TARGET"' in installer, "FCC installer does not require Gateway Activity")
require('stage_install_component "$WORK_DIR/localtx.php" "$LOCALTX_TARGET"' in installer, "FCC installer does not install its legend patch")
php = shutil.which("php")
if php:
    subprocess.run([php, str(ROOT / "tests/test-fcc-country-lookup.php")], check=True)
    subprocess.run([php, str(ROOT / "tests/test-fcc-custom-descriptions.php")], check=True)
    subprocess.run([php, str(ROOT / "tests/test-fcc-manual-callsign-names.php")], check=True)
else:
    print("SKIP: PHP country/custom-description runtime cases (php unavailable)")
print("PASS: surgical FCC Gateway Activity patcher tests")
