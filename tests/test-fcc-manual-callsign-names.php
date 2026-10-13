<?php
// Version: 1.0.0
// SPDX-License-Identifier: MIT
$path = tempnam(sys_get_temp_dir(), 'dvs-manual-callsigns-');
$descriptionPath = tempnam(sys_get_temp_dir(), 'dvs-custom-callsigns-');
$fccPath = tempnam(sys_get_temp_dir(), 'dvs-empty-fcc-');
file_put_contents($path, "# manually entered names\nVK2XYZ = Taylor Operator\n");
file_put_contents($descriptionPath, "# custom descriptions\n");
file_put_contents($fccPath, '');
$dvsModsManualCallsignNamesPath = $path;
$dvsModsCustomCallsignDescriptionPath = $descriptionPath;
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
requireManualName(true, dvsModsSaveManualCallsignName('K1ZZZ', 'Zed Operator', $path), 'second manual name save failed');
$saved = file_get_contents($path);
if (strpos($saved, "N0MISSING = Avery Example\n") === false) { fwrite(STDERR, "FAIL: saved entry format was incorrect\n"); exit(1); }
$savedCalls = array();
foreach (file($path, FILE_IGNORE_NEW_LINES) as $line) {
    if (preg_match('/^([A-Z0-9]{3,10}) = /', $line, $match)) { $savedCalls[] = $match[1]; }
}
$sortedCalls = $savedCalls;
sort($sortedCalls, SORT_STRING);
if ($savedCalls !== $sortedCalls) { fwrite(STDERR, "FAIL: saved callsign entries are not alphabetically sorted\n"); exit(1); }
requireManualName('Enter a name of 1 to 100 characters without tabs or line breaks.', dvsModsSaveManualCallsignName('N0MISSING', "Bad\nName", $path), 'control characters were accepted');
requireManualName('A name is already available in the local FCC/DMR databases.', dvsModsSaveManualCallsignName('K1ABC', 'Wrong Override', $path), 'database-backed name was allowed to be overridden');
requireManualName(true, dvsModsSaveCustomCallsignDescription('XLX618', 'US HemetHangout', $descriptionPath), 'custom description save failed');
requireManualName('US HemetHangout', dvsModsCustomCallsignDescription('XLX618'), 'saved custom description was not readable');
requireManualName('A custom description is already available for this callsign.', dvsModsSaveManualCallsignName('XLX618', 'Wrong File', $path), 'manual name was allowed to duplicate a custom description');
requireManualName('A name is already available in the local FCC/DMR databases.', dvsModsSaveCustomCallsignDescription('K1ABC', 'Wrong Override', $descriptionPath), 'database-backed name was allowed to be overridden by a custom description');
requireManualName('Enter a description of 1 to 80 characters without tabs, line breaks, or equals signs.', dvsModsSaveCustomCallsignDescription('SRVPROBA', "Bad\nDescription", $descriptionPath), 'control characters were accepted in custom description');
@unlink($path);
@unlink($descriptionPath);
@unlink($fccPath);
echo "PASS: manual callsign names, database precedence, normalization, and safe writes\n";
?>
