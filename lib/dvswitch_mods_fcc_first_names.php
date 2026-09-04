<?php
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jeff Milne, KE2HNI
// DVSwitch-Mods: fixed-record FCC first-name lookup v1

function dvsModsDmrIdCallsign($rawCallsign) {
    static $cache = array();
    $value = trim((string)$rawCallsign);
    if (!preg_match('/^[0-9]{7}$/D', $value)) { return $value; }
    if (array_key_exists($value, $cache)) { return $cache[$value]; }

    global $dmrIDline;
    $database = isset($dmrIDline) && is_string($dmrIDline) ? $dmrIDline : false;
    if ($database === false) {
        $path = defined('DMRIDDATPATH') ? DMRIDDATPATH.'/DMRIds.dat' : '/var/lib/mmdvm/DMRIds.dat';
        $database = @file_get_contents($path);
    }
    if (!is_string($database) || $database === '') { return $cache[$value] = $value; }

    $pattern = '/(?:\A|\R)'.preg_quote($value, '/').'[ \t]+([A-Z0-9]{3,10})(?:[ \t]+[^\r\n]*)?(?=\R|\z)/i';
    $count = preg_match_all($pattern, $database, $matches);
    if ($count !== 1) { return $cache[$value] = $value; }
    $callsign = strtoupper($matches[1][0]);
    if (!preg_match('/^(?=.*[A-Z])(?=.*[0-9])[A-Z0-9]{3,10}$/D', $callsign)) {
        return $cache[$value] = $value;
    }
    return $cache[$value] = $callsign;
}

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
