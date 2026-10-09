<?php
// Version: 1.0.0
// SPDX-License-Identifier: MIT
// Regression coverage for CTY.DAT parsing used by the dashboard country fallback.

require __DIR__.'/../lib/dvswitch_mods_fcc_first_names.php';

$fixture = <<<'CTY'
Test Country:  K,KA-KZ,
  W[AEG],N[AEG];
Second Entity:  VE,VA;
Special Entity:  =K1ABC;
CTY
;
$path = tempnam(sys_get_temp_dir(), 'dvswitch-cty-test-');
if ($path === false) { fwrite(STDERR, "FAIL: could not create fixture\n"); exit(1); }
file_put_contents($path, "AD1C test header\nArgentina: LU;\n".$fixture);
$dvsModsFccCountryDatabasePath = $path;

$cases = array(
    'K1ABC' => 'Special Entity', // exact override after ordinary prefixes
    'K2XYZ' => 'Test Country', // simple prefix
    'KA1XYZ' => 'Test Country', // CTY range prefix
    'W1ABC' => 'Test Country', // bracket character set
    'WG1ABC' => 'Test Country', // bracket character set
    'WB1ABC' => '', // letters outside the bracket set must not use the base prefix
    'N1ABC' => 'Test Country',
    'NE1ABC' => 'Test Country',
    'VE3ABC' => 'Second Entity', // continuation line
    'VA2ABC' => 'Second Entity',
);
$failed = false;
foreach ($cases as $callsign => $expected) {
    $actual = dvsModsFccCountry($callsign);
    if ($actual !== $expected) {
        fwrite(STDERR, "FAIL: $callsign resolved to '$actual', expected '$expected'\n");
        $failed = true;
    }
}
unlink($path);
if ($failed) { exit(1); }
echo "PASS: CTY.DAT country lookup tests\n";
?>
