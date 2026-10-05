<?php
// SPDX-License-Identifier: MIT
$path = tempnam(sys_get_temp_dir(), 'dvs-custom-callsigns-');
file_put_contents($path, "# test descriptions\n9999\tNXDN Announcement\nH4LNK\tYSF Link\nN0CALL\tP25 Announcement\nAMERICALNK\tAmerica Link\nBAD\t\nINVALID DESC\tignored\n");
$dvsModsCustomCallsignDescriptionPath = $path;
$dmrIDline = "";
require dirname(__DIR__).'/lib/dvswitch_mods_fcc_first_names.php';
function requireDescription($expected, $actual, $message) {
    if ($expected !== $actual) { fwrite(STDERR, "FAIL: $message (expected ".var_export($expected, true).", received ".var_export($actual, true).")\n"); exit(1); }
}
foreach (array('9999' => 'NXDN Announcement', 'H4LNK' => 'YSF Link', 'N0CALL' => 'P25 Announcement', 'AMERICALNK' => 'America Link') as $callsign => $description) {
    requireDescription($description, dvsModsCustomCallsignDescription($callsign), "custom description not found for $callsign");
}
requireDescription(false, dvsModsCustomCallsignDescription('UNKNOWN'), 'unknown callsign unexpectedly matched');
@unlink($path);
echo "PASS: custom callsign description lookup tests\n";
?>
