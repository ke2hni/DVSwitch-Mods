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
require(changed.index("$dvsModsFirstName = dvsModsFccFirstName") < changed.index("dvsModsCustomCallsignDescription($listElem[2])") < changed.index("dvsModsManualCallsignName($listElem[2])"), "lookup precedence is not FCC/DMR, custom descriptions, then manual names")
require("$dvsModsNameHtml = '<button type=\"button\"" in changed and "fetch(&#39;callsign-lookup.php&#39;" in changed and "&#39;data-callsign&#39;" in changed and "&#39;data-identifier&#39;" in changed, "unknown name marker is not clickable with separate callsign and exact-identifier values")
require("var k=t===&#39;1&#39;?c:i" in changed and "encodeURIComponent(k)" in changed, "custom-description save does not retain the exact dashboard identifier")
require("operator name (callsign-lookup.tsv)" in changed and "custom description (callsign-descriptions.tsv)" in changed and "&amp;type=&#39;+encodeURIComponent(t)" in changed, "unknown marker does not offer separate operator-name and custom-description saves")
require(patcher.MARKER.endswith("v6"), "FCC patch version was not advanced for NXDN ID lookup")
require("dvsModsNxdnIdCallsign($listElem[2])" in changed, "NXDN resolver missing")
require('strtoupper(trim((string)$listElem[1])) === "NXDN"' in changed, "NXDN resolution is not limited to NXDN rows")
require(changed.index('strtoupper(trim((string)$listElem[1])) === "NXDN"') < changed.index('dvsModsNxdnIdCallsign($listElem[2])') < changed.index('dvsModsDmrIdCallsign($listElem[2])'), "NXDN resolver is not correctly dispatched before DMR fallback")
require("dvsModsDmrIdCallsign($listElem[2])" in changed, "DMR resolver missing")
require(changed.count("width:12ch;min-width:12ch;max-width:12ch") == 1, "Name-cell width and wrap limit missing")
require(changed.count("overflow-wrap:anywhere") == 1, "Name-cell overflow wrapping missing")
require("width:640px" not in changed, "fixture unexpectedly contained layout width")
require(patcher.patch_text(changed) == changed, "patch is not idempotent")
existing_dashboard_without_nxdn = changed.replace(
    '''if (strtoupper(trim((string)$listElem[1])) === "NXDN") {
                    $listElem[2] = dvsModsNxdnIdCallsign($listElem[2]);
                } else {
                    $listElem[2] = dvsModsDmrIdCallsign($listElem[2]);
                }
''', '                    $listElem[2] = dvsModsDmrIdCallsign($listElem[2]);\n', 1)
require("dvsModsNxdnIdCallsign($listElem[2])" not in existing_dashboard_without_nxdn,
        "failed to prepare the installed FCC dashboard missing only NXDN dispatch")
repaired_existing_dashboard = patcher.patch_text(existing_dashboard_without_nxdn)
require("dvsModsNxdnIdCallsign($listElem[2])" in repaired_existing_dashboard and
        "dvsModsDmrIdCallsign($listElem[2])" in repaired_existing_dashboard,
        "existing FCC dashboard missing NXDN dispatch was not upgraded")
require(patcher.patch_text(repaired_existing_dashboard) == repaired_existing_dashboard,
        "NXDN dispatch repair of an existing dashboard is not idempotent")
legacy_country_upgrade = changed.replace(patcher.NAME_BLOCK, patcher.OLD_NAME_BLOCK, 1).replace(patcher.MARKER, patcher.PREVIOUS_MARKER, 1)
require(legacy_country_upgrade != changed, "failed to prepare legacy country-fallback fixture")
require(patcher.patch_text(legacy_country_upgrade) == changed, "existing country-fallback installation was not upgraded")
previous_manual_install = changed.replace(patcher.NAME_BLOCK, patcher.PREVIOUS_NAME_BLOCK, 1).replace(patcher.MARKER, patcher.PREVIOUS_MARKER, 1)
require(patcher.patch_text(previous_manual_install) == changed,
        "existing manual-name installation was not upgraded to separate custom-description saves and corrected precedence")
previous_exact_identifier_install = changed.replace(patcher.NAME_BLOCK, patcher.PREVIOUS_NAME_BLOCK, 1).replace(patcher.MARKER, patcher.PREVIOUS_NAME_MARKER, 1)
require(patcher.patch_text(previous_exact_identifier_install) == changed,
        "existing v4 manual-entry installation was not upgraded to preserve exact custom identifiers")
legacy_partial_name = patcher.OLD_COUNTRY_BLOCK.replace(
    "\n                $dvsModsCountry", "\n                // retained prior dashboard formatting hook\n                $dvsModsCountry", 1)
legacy_existing_html = changed.replace(patcher.NAME_BLOCK, legacy_partial_name, 1).replace(patcher.MARKER, patcher.PREVIOUS_NAME_MARKER, 1)
require(patcher.patch_text(legacy_existing_html) == changed,
        "legacy Name block with existing HTML output was not safely upgraded")
legacy_without_known_boundary = legacy_existing_html.replace(
    "if (strlen($listElem[4]) == 1) { $listElem[4] = str_pad($listElem[4], 8, \" \", STR_PAD_LEFT); }\n", "", 1)
require(patcher.patch_text(legacy_without_known_boundary) == changed.replace(
    "if (strlen($listElem[4]) == 1) { $listElem[4] = str_pad($listElem[4], 8, \" \", STR_PAD_LEFT); }\n", "", 1),
        "legacy Name block upgrade incorrectly depends on a later activity-row boundary")

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
    localtx.write_text('<div><b>Legend:</b> <b>---</b> = No usable worldwide DMR ID or FCC name data available, Maybe an International Callsign.</div>', encoding="utf-8")
    subprocess.run(["python3", str(ROOT / "lib/patch_dashboard_first_names.py"), "--lh", str(path), "--localtx", str(localtx)], check=True)
    raw = path.read_bytes()
    require(b"\r\n" in raw and b"\n" not in raw.replace(b"\r\n", b""), "CRLF was not preserved")
    legend = localtx.read_text(encoding="utf-8")
    require(patcher.LEGEND_MARKER in legend and "/etc/dvswitch-mods/callsign-lookup.tsv" in legend, "manual callsign legend was not added")
    require("Operator name entered manually and saved in the local callsign names file" in legend and ">file location</span>" in legend,
            "manual callsign legend does not explain the marker and file path")
    require("dvsModsCallsignFileTip:hover:after" in legend and "data-tip=\"Manual operator names file: /etc/dvswitch-mods/callsign-lookup.tsv\"" in legend,
        "manual callsign file path does not have a visible hover/focus popup")
    require("Click --- to add an entry." in legend, "legend does not explain that --- is clickable")
    require(legend.count("width:3ch;text-align:right") == 2, "equals signs do not align across the --- and * legend rows")
    require(legend.count("margin-left:8ch") == 2, "both legend data rows are not indented by eight character widths")
    require(patcher.patch_legend_text(legend) == legend, "aligned legend patch is not idempotent")

# Stock DVSwitch Local Activity has no Legend block, but has a unique closing anchor.
stock_localtx = ('''<div>
<span style="font-weight: bold;font-size:14px;">Local Activity</span>
<fieldset><table>
  </table>
</fieldset>
</div>
<br>
''')
stock_legend = patcher.patch_legend_text(stock_localtx)
require(stock_legend.count("<b>Legend:</b>") == 1, "fresh stock Local Activity did not receive one legend")
require(patcher.LEGEND_MARKER in stock_legend and "Click --- to add an entry." in stock_legend,
        "fresh stock Local Activity legend is missing manual-entry guidance")
require(stock_legend.index("</fieldset>") < stock_legend.index(patcher.LEGEND_MARKER),
        "fresh stock Local Activity legend was not placed after the activity table")
require(patcher.patch_legend_text(stock_legend) == stock_legend,
        "fresh stock Local Activity legend insertion is not idempotent")

legacy_legend = ('<div><b>Legend:</b> <b>---</b> = no data<br>\n  <b>*</b> = Name entered and saved by you in the local callsign file. '
                 '<span title="Manually entered callsign names are stored in /etc/dvswitch-mods/callsign-lookup.tsv.">Database</span>\n  '
                 '<!-- DVSwitch-Mods: manual callsign names legend v1 -->\n</div>')
upgraded_legend = patcher.patch_legend_text(legacy_legend)
require(patcher.LEGEND_MARKER in upgraded_legend and "manual callsign names legend v1" not in upgraded_legend,
        "existing manual callsign legend marker was not upgraded")
require(upgraded_legend.count("width:3ch;text-align:right") == 2,
        "existing legend --- and * terms were not aligned during upgrade")
require(upgraded_legend.count("margin-left:8ch") == 2,
        "existing legend rows were not shifted right during upgrade")
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
require("Operator name entered manually and saved in the local callsign names file" in upgraded_v3_legend,
        "v3 legend wording was not updated")
require(patcher.patch_legend_text(upgraded_v3_legend) == upgraded_v3_legend,
        "upgraded v3 legend is not idempotent")

# This is the combined legend shape left behind when the Target installer sees
# its marker and preserves the FCC-owned manual-name row.
installed_combined_legend = ('''<div style="margin:3px 0 0 14px;font-size:10px;line-height:1.3;text-align:left;white-space:normal;overflow-wrap:anywhere;">
  <b>Legend:</b> <span style="display:inline-block;width:3ch;text-align:right;"><b>---</b></span> = No usable worldwide DMR ID or FCC name data available, Maybe an International Callsign.<br>
  <span style="display:inline-block;width:3ch;text-align:right;"><b>*</b></span> = Name entered and saved by you in the local callsign file. <span title="Manually entered callsign names are stored in /etc/dvswitch-mods/callsign-lookup.tsv.">Database</span>
  <!-- DVSwitch-Mods: manual callsign names legend v3 -->
</div>''')
fixed_combined_legend = patcher.patch_legend_text(installed_combined_legend)
require("Maybe an International Callsign" not in fixed_combined_legend and "No name found in the local DMR ID or FCC data; country shown when available." in fixed_combined_legend,
        "combined installed legend kept the old --- description")
require("Name entered by you in the local callsign file" not in fixed_combined_legend and ">file location</span>" in fixed_combined_legend,
        "combined installed legend kept the old manual-name wording")
require(fixed_combined_legend.count("width:3ch;text-align:right") == 2,
        "combined installed legend does not align the --- and * rows")
require(fixed_combined_legend.count("margin-left:8ch") == 2,
        "combined installed legend data rows were not shifted right")
require(patcher.patch_legend_text(fixed_combined_legend) == fixed_combined_legend,
        "combined installed legend migration is not idempotent")
unpatched_combined_legend = patcher.unpatch_legend_text(fixed_combined_legend)
require(patcher.LEGEND_MARKER not in unpatched_combined_legend and "dvsModsCallsignFileTip" not in unpatched_combined_legend,
        "manual-name legend removal left its marker or tooltip styles behind")

test7_legend = ('''<div style="margin:3px 0 0 14px;font-size:10px;line-height:1.3;text-align:left;white-space:normal;overflow-wrap:anywhere;">
  <b>Legend:</b><br>
  <span style="display:inline-block;width:3ch;text-align:right;"><b>---</b></span> = No name found in the local DMR ID or FCC data; country shown when available.<br>
  <span style="display:inline-block;width:3ch;text-align:right;"><b>*</b></span> = Name entered manually and saved in the local callsign names file (<span title="Manual callsign names are stored in /etc/dvswitch-mods/callsign-lookup.tsv.">file location</span>)<br>
  <!-- DVSwitch-Mods: manual callsign names legend v4 -->
</div>''')
upgraded_test7_legend = patcher.patch_legend_text(test7_legend)
require("Click --- to add an entry." in upgraded_test7_legend and "dvsModsCallsignFileTip:hover:after" in upgraded_test7_legend
        and "Operator name entered manually" in upgraded_test7_legend,
        "Test7 combined legend was not upgraded with the click hint and visible path popup")
require(patcher.patch_legend_text(upgraded_test7_legend) == upgraded_test7_legend,
        "Test7 combined legend upgrade is not idempotent")

installer = (ROOT / "mod-dashboard-fcc-first-names.sh").read_text()
require("grep -Fq 'dvsModsNxdnIdCallsign($listElem[2])' \"$target\"" in installer,
        "FCC installer does not verify NXDN resolver is present in deployed lh.php")
require('grep -Fq \'strtoupper(trim((string)$listElem[1])) === "NXDN"\' "$target"' in installer,
        "FCC installer does not verify NXDN-only dashboard dispatch")
require("DMR/NXDN callsign resolution" in installer,
        "FCC install/check output does not identify NXDN integration")
require('cmp -s "$TRANSACTION_LIBRARY" "$TRANSACTION_TARGET" || die' not in installer,
        "FCC dashboard installer still blocks a structurally compatible transaction helper revision")
require('transaction_library_supported "$TRANSACTION_TARGET"' in installer,
        "FCC dashboard installer does not validate the installed transaction helper structurally")
custom_file = (ROOT / "data/callsign-descriptions.tsv").read_text()
for entry in ("9999 = Announcement", "H4MLNK = YSF Link", "N0CALL = Announcement", "AMERICALNK = America Link"):
    require(entry in custom_file, "starter custom-description entry missing: " + entry)
require('readonly CALLSIGN_DESCRIPTIONS_TARGET="/etc/dvswitch-mods/callsign-descriptions.tsv"' in installer, "custom file install path missing")
require('readonly CALLSIGN_DESCRIPTIONS_MERGER="$SCRIPT_DIR/lib/merge_callsign_descriptions.py"' in installer, "custom-description merge helper is missing")
require('if [[ ! -e "$CALLSIGN_DESCRIPTIONS_TARGET" && ! -L "$CALLSIGN_DESCRIPTIONS_TARGET" ]]; then' in installer, "installer does not preserve existing user descriptions")
require('cp -a -- "$CALLSIGN_DESCRIPTIONS_TARGET" "$custom_temporary"' in installer, "uninstall does not preserve a user's custom descriptions")
require('"$CALLSIGN_DESCRIPTIONS_TARGET" "$CALLSIGN_NAMES_TARGET"; do backup_target "$target"; done' in installer, "uninstall safety backup omits user TSV files")
require('Custom callsign descriptions: editable file present' in installer, "--check does not report custom file state")
require('descriptions_starter_missing=$(python3 "$CALLSIGN_DESCRIPTIONS_MERGER" --check "$CALLSIGN_DESCRIPTIONS_TARGET" "$CALLSIGN_DESCRIPTIONS_SOURCE")' in installer, "install/check does not detect missing starter descriptions")
require('python3 "$CALLSIGN_DESCRIPTIONS_MERGER" --merge "$CALLSIGN_DESCRIPTIONS_TARGET" "$CALLSIGN_DESCRIPTIONS_SOURCE"' in installer, "installer does not merge starter descriptions")
require('backup_target "$CALLSIGN_DESCRIPTIONS_TARGET"' in installer, "installer does not back up the existing custom descriptions file before merge")
require('readonly CALLSIGN_NAMES_TARGET="/etc/dvswitch-mods/callsign-lookup.tsv"' in installer, "manual callsign names file path missing")
require('readonly CALLSIGN_NAMES_STARTER_SOURCE="$SCRIPT_DIR/data/callsign-lookup.tsv"' in installer, "manual-name starter source is missing")
require('readonly CALLSIGN_NAMES_MERGER="$SCRIPT_DIR/lib/merge_callsign_lookup.py"' in installer, "manual-name merge helper is missing")
manual_names_php = (ROOT / "lib/dvswitch_mods_fcc_first_names.php").read_text()
require('usort($entries, function ($left, $right)' in manual_names_php, "manual-name saves do not sort callsigns alphabetically")
require('names_starter_missing=$(python3 "$CALLSIGN_NAMES_MERGER" --check "$CALLSIGN_NAMES_TARGET" "$CALLSIGN_NAMES_STARTER_SOURCE")' in installer, "install/check does not detect missing starter names")
require('names_sorted=$(python3 "$CALLSIGN_NAMES_MERGER" --is-sorted "$CALLSIGN_NAMES_TARGET" "$CALLSIGN_NAMES_STARTER_SOURCE")' in installer, "install/check does not detect callsign order")
require('python3 "$CALLSIGN_NAMES_MERGER" --merge "$CALLSIGN_NAMES_TARGET" "$CALLSIGN_NAMES_STARTER_SOURCE"' in installer, "installer does not merge starter names")
require('backup_target "$CALLSIGN_NAMES_TARGET"' in installer, "installer does not back up the existing manual names file before merge")
require('SCRIPT_VERSION="1.6.3"' in installer, "FCC installer version was not advanced for callsign sorting")
require('readonly LOCALTX_TARGET="/usr/share/dvswitch/include/localtx.php"' in installer, "legend dashboard file target missing")
require('dvsModsSaveManualCallsignName($_POST[\'callsign\'] ?? \'\', $_POST[\'name\'] ?? \'\')' in (ROOT / "lib/dvswitch_mods_callsign_name_save.php").read_text(), "server-side manual name endpoint is missing")
save_endpoint = (ROOT / "lib/dvswitch_mods_callsign_name_save.php").read_text()
require('dvsModsSaveCustomCallsignDescription($_POST[\'callsign\'] ?? \'\', $_POST[\'name\'] ?? \'\')' in save_endpoint and "$_POST['type']" in save_endpoint,
        "save endpoint does not route custom descriptions separately")
require('chown root:www-data "$CALLSIGN_DESCRIPTIONS_TARGET"; chmod 0660 "$CALLSIGN_DESCRIPTIONS_TARGET"' in installer,
        "installer does not grant the dashboard writer access to the custom-description TSV")
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
