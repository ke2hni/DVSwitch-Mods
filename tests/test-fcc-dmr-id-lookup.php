<?php
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jeff Milne, KE2HNI

define('DMRIDDATPATH', '/nonexistent-dvswitch-mods-test-path');
require dirname(__DIR__).'/lib/dvswitch_mods_fcc_first_names.php';

function requireSame($expected, $actual, $message) {
    if ($expected !== $actual) {
        fwrite(STDERR, "FAIL: $message (expected $expected, received $actual)\n");
        exit(1);
    }
}

$dmrIDline = "1023007 VA3BOC Hans Juergen\n3220537 N4YZP Walter\n3220538 KI5FFE Robert\n";
requireSame('N4YZP', dvsModsDmrIdCallsign('3220537'), 'observed DMR ID was not resolved');
requireSame('KI5FFE', dvsModsDmrIdCallsign(' 3220538 '), 'trimmed DMR ID was not resolved');
requireSame('KE2HNI/INFO', dvsModsDmrIdCallsign('KE2HNI/INFO'), 'ordinary suffixed callsign changed');
requireSame('123456', dvsModsDmrIdCallsign('123456'), 'non-seven-digit value changed');
requireSame('9999999', dvsModsDmrIdCallsign('9999999'), 'missing DMR ID changed');

$dmrIDline .= "4000001 BAD-CALL Name\n";
requireSame('4000001', dvsModsDmrIdCallsign('4000001'), 'invalid mapped callsign was accepted');
$dmrIDline .= "5000001 K1ABC One\n5000001 K2ABC Two\n";
requireSame('5000001', dvsModsDmrIdCallsign('5000001'), 'duplicate DMR ID was accepted');

echo "PASS: FCC DMR-ID callsign resolver tests\n";
?>
