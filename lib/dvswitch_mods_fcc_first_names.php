<?php
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jeff Milne, KE2HNI
// DVSwitch-Mods: fixed-record FCC first-name lookup v1

function dvsModsFccFirstName($rawCallsign) {
    static $cache = array();
    $callsign = strtoupper(trim((string)$rawCallsign));
    $dash = strpos($callsign, '-');
    if ($dash !== false) { $callsign = substr($callsign, 0, $dash); }
    $slash = strpos($callsign, '/');
    if ($slash !== false) { $callsign = substr($callsign, 0, $slash); }
    if (!preg_match('/^[A-Z0-9]{3,10}$/', $callsign)) { return '---'; }
    if (isset($cache[$callsign])) { return $cache[$callsign]; }

    $path = '/var/lib/mmdvm/dvswitch-mods-fcc-first-names.dat';
    $recordSize = 52;
    $size = @filesize($path);
    if ($size === false || $size < $recordSize || ($size % $recordSize) !== 0) {
        return $cache[$callsign] = '---';
    }
    $handle = @fopen($path, 'rb');
    if ($handle === false) { return $cache[$callsign] = '---'; }
    $low = 0;
    $high = intdiv($size, $recordSize) - 1;
    $result = '---';
    while ($low <= $high) {
        $middle = intdiv($low + $high, 2);
        if (fseek($handle, $middle * $recordSize) !== 0) { break; }
        $record = fread($handle, $recordSize);
        if ($record === false || strlen($record) !== $recordSize) { break; }
        $candidate = rtrim(substr($record, 0, 10));
        $comparison = strcmp($callsign, $candidate);
        if ($comparison === 0) {
            $name = rtrim(substr($record, 11, 40));
            if ($name !== '') { $result = $name; }
            break;
        }
        if ($comparison < 0) { $high = $middle - 1; }
        else { $low = $middle + 1; }
    }
    fclose($handle);
    return $cache[$callsign] = $result;
}
?>
