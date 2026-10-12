<?php
// Version: 1.0.0
// SPDX-License-Identifier: MIT
$path = tempnam(sys_get_temp_dir(), 'dvs-manual-callsigns-');
$fccPath = tempnam(sys_get_temp_dir(), 'dvs-empty-fcc-');
file_put_contents($path, "# manually entered names\nVK2XYZ = Taylor Operator\n");
file_put_contents($fccPath, '');
$dvsModsManualCallsignNamesPath = $path;
$dvsModsFccFirstNamesPath = $fccPath;
$dmrIDline = "3160001 VK2XYZ Alex Example\n";
require dirname(__DIR__).'/lib/dvswitch_mods_fcc_first_names.php';
function requireManualName($expected, $actual, $message) {
    if ($expected !== $actual) { fwrite(STDERR, "FAIL: $message (expected ".var_export($expected, true).", received ".var_export($actual, true).")\n"); exit(1); }
}
requireManualName('Alex', dvsModsFccFirstName('VK2XYZ'), 'DMR database name should be resolved before manual name');
requireManualName('Taylor Operator', dvsModsManualCallsignName('VK2XYZ/P'), 'manual file suffix normalization failed');
requireManualName(false, dvsModsManualCallsignName('N0MISSING'), 'missing manual name unexpectedly matched');
requireManualName('Avery Example', dvsModsSaveManualCallsignName('N0MISSING', 'Avery Example', $path), 'manual name save failed');
$saved = file_get_contents($path);
if (strpos($saved, "N0MISSING = Avery Example\n") === false) { fwrite(STDERR, "FAIL: saved entry format was incorrect\n"); exit(1); }
requireManualName('Enter a name of 1 to 100 characters without tabs or line breaks.', dvsModsSaveManualCallsignName('N0MISSING', "Bad\nName", $path), 'control characters were accepted');
requireManualName('A name is already available in the local FCC/DMR databases.', dvsModsSaveManualCallsignName('K1ABC', 'Wrong Override', $path), 'database-backed name was allowed to be overridden');
@unlink($path);
@unlink($fccPath);
echo "PASS: manual callsign names, database precedence, normalization, and safe writes\n";
?>
