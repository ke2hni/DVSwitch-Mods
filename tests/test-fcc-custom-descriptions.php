<?php
// Version: 1.0.0
// SPDX-License-Identifier: MIT
$path = tempnam(sys_get_temp_dir(), 'dvs-custom-callsigns-');
file_put_contents($path, "# test descriptions\n9999 = Announcement\nH4MLNK = YSF Link\nN0CALL = Announcement\nAMERICALNK = America Link\nAL-LINK = Alabama Link YSF Reflector Dashboard\nTABTEST\tLegacy Tab Entry\nBAD = \nINVALID DESC = ignored\n");
$dvsModsCustomCallsignDescriptionPath = $path;
$dmrIDline = "";
require dirname(__DIR__).'/lib/dvswitch_mods_fcc_first_names.php';
function requireDescription($expected, $actual, $message) {
    if ($expected !== $actual) { fwrite(STDERR, "FAIL: $message (expected ".var_export($expected, true).", received ".var_export($actual, true).")\n"); exit(1); }
}
foreach (array('9999' => 'Announcement', 'H4MLNK' => 'YSF Link', 'N0CALL' => 'Announcement', 'AMERICALNK' => 'America Link', 'AL-LINK' => 'Alabama Link YSF Reflector Dashboard', 'TABTEST' => 'Legacy Tab Entry') as $callsign => $description) {
    requireDescription($description, dvsModsCustomCallsignDescription($callsign), "custom description not found for $callsign");
}
requireDescription(false, dvsModsCustomCallsignDescription('UNKNOWN'), 'unknown callsign unexpectedly matched');
$savePath = $path.'.save';
requireDescription(true, dvsModsSaveCustomCallsignDescription('AL-LINK', 'Alabama Link', $savePath), 'hyphenated identifier could not be saved');
requireDescription("AL-LINK = Alabama Link\n", file_get_contents($savePath), 'hyphenated identifier was not saved exactly');
@unlink($savePath);
@unlink($path);
echo "PASS: custom callsign description lookup tests\n";
?>
