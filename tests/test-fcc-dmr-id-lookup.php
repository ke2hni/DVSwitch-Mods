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

$dmrIDline = "1023007 VA3BOC Hans Juergen\n3220537 N4YZP Walter\n3220538 KI5FFE Robert\n3300360 WP4J Manuel\n4000001 BAD-CALL Name\n5000001 K1ABC One\n5000001 K2ABC Two\n5151594 DX1E Elite Hamster Club Inc\n5301034 ZL2BEZ Paul\n5301049 ZL2BEZ Paul\n6000001 K1DUP First Value\n6000002 K1DUP Second Value\n7000001 K1BAD Unknown\n7000002 K2BAD ---\n7000003 K3BAD 12345\n8000001 SP1ABC Łukasz\n";
requireSame('N4YZP', dvsModsDmrIdCallsign('3220537'), 'observed DMR ID was not resolved');
requireSame('KI5FFE', dvsModsDmrIdCallsign(' 3220538 '), 'trimmed DMR ID was not resolved');
requireSame('KE2HNI/INFO', dvsModsDmrIdCallsign('KE2HNI/INFO'), 'ordinary suffixed callsign changed');
requireSame('123456', dvsModsDmrIdCallsign('123456'), 'non-seven-digit value changed');
requireSame('9999999', dvsModsDmrIdCallsign('9999999'), 'missing DMR ID changed');
requireSame('Hans Juergen', dvsModsFccFirstName('VA3BOC'), 'international multi-part name was not preserved');
requireSame('Manuel', dvsModsFccFirstName('WP4J'), 'Puerto Rico DMR name was not resolved');
requireSame('Elite Hamster Club Inc', dvsModsFccFirstName('DX1E'), 'descriptive DMR name was shortened');
requireSame('Paul', dvsModsFccFirstName('ZL2BEZ'), 'identical duplicate DMR names were rejected');
requireSame(false, dvsModsDmrName('K1DUP'), 'conflicting duplicate DMR names were accepted');
requireSame(false, dvsModsDmrName('K1BAD'), 'Unknown placeholder was accepted');
requireSame(false, dvsModsDmrName('K2BAD'), 'dash placeholder was accepted');
requireSame(false, dvsModsDmrName('K3BAD'), 'numeric garbage was accepted');
requireSame('Łukasz', dvsModsFccFirstName('SP1ABC'), 'international UTF-8 name was rejected');

requireSame('4000001', dvsModsDmrIdCallsign('4000001'), 'invalid mapped callsign was accepted');
requireSame('5000001', dvsModsDmrIdCallsign('5000001'), 'duplicate DMR ID was accepted');

echo "PASS: FCC DMR-ID callsign resolver tests\n";
?>
