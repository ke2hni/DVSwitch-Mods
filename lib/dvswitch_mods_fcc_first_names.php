<?php
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jeff Milne, KE2HNI
// DVSwitch-Mods: worldwide DMR and FCC name lookup v2

function dvsModsFccDmrDatabase() {
    static $database = null;
    if ($database !== null) { return $database; }

    global $dmrIDline;
    if (isset($dmrIDline) && is_string($dmrIDline) && $dmrIDline !== '') {
        return $database = $dmrIDline;
    }
    $path = defined('DMRIDDATPATH') ? DMRIDDATPATH.'/DMRIds.dat' : '/var/lib/mmdvm/DMRIds.dat';
    $contents = @file_get_contents($path);
    return $database = is_string($contents) ? $contents : '';
}

function dvsModsFccUsableDmrName($rawName, $callsign) {
    $name = preg_replace('/[ \t]+/', ' ', trim((string)$rawName));
    if (!is_string($name) || $name === '' || strlen($name) > 120) { return false; }
    $upper = strtoupper($name);
    $placeholders = array('UNKNOWN', 'NONE', 'N/A', 'NA', 'NULL', 'NO NAME', 'NOT REGISTERED', '-', '--', '---');
    if (in_array($upper, $placeholders, true) || $upper === strtoupper($callsign)) { return false; }
    if (preg_match('/[\x00-\x1F\x7F]/', $name) || preg_match('/\p{L}/u', $name) !== 1) { return false; }
    return $name;
}

function dvsModsFccDmrNameCache($callsign, $value = false, $store = false) {
    static $cache = array();
    if ($store) { $cache[$callsign] = $value; }
    return array_key_exists($callsign, $cache) ? $cache[$callsign] : false;
}

function dvsModsFccDmrName($rawCallsign) {
    static $cache = array();
    $callsign = strtoupper(trim((string)$rawCallsign));
    $dash = strpos($callsign, '-');
    if ($dash !== false) { $callsign = substr($callsign, 0, $dash); }
    $slash = strpos($callsign, '/');
    if ($slash !== false) { $callsign = substr($callsign, 0, $slash); }
    if (!preg_match('/^(?=.*[A-Z])(?=.*[0-9])[A-Z0-9]{3,10}$/D', $callsign)) { return false; }
    if (array_key_exists($callsign, $cache)) { return $cache[$callsign]; }
    $remembered = dvsModsFccDmrNameCache($callsign);
    if ($remembered !== false) { return $cache[$callsign] = $remembered; }

    $database = dvsModsFccDmrDatabase();
    if ($database === '') { return $cache[$callsign] = false; }
    $pattern = '/(?:\A|\R)[0-9]{7}[ \t]+'.preg_quote($callsign, '/').'[ \t]+([^\r\n]*)(?=\R|\z)/i';
    $count = preg_match_all($pattern, $database, $matches);
    if ($count < 1) { return $cache[$callsign] = false; }

    $resolved = false;
    foreach ($matches[1] as $rawName) {
        $name = dvsModsFccUsableDmrName($rawName, $callsign);
        if ($name === false) { continue; }
        if ($resolved !== false && strcasecmp($resolved, $name) !== 0) {
            return $cache[$callsign] = false;
        }
        $resolved = $name;
    }
    return $cache[$callsign] = $resolved;
}

function dvsModsDmrIdCallsign($rawCallsign) {
    static $cache = array();
    $value = trim((string)$rawCallsign);
    if (!preg_match('/^[0-9]{7}$/D', $value)) { return $value; }
    if (array_key_exists($value, $cache)) { return $cache[$value]; }

    $database = dvsModsFccDmrDatabase();
    if ($database === '') { return $cache[$value] = $value; }

    $pattern = '/(?:\A|\R)'.preg_quote($value, '/').'[ \t]+([A-Z0-9]{3,10})(?:[ \t]+([^\r\n]*))?(?=\R|\z)/i';
    $count = preg_match_all($pattern, $database, $matches);
    if ($count !== 1) { return $cache[$value] = $value; }
    $callsign = strtoupper($matches[1][0]);
    if (!preg_match('/^(?=.*[A-Z])(?=.*[0-9])[A-Z0-9]{3,10}$/D', $callsign)) {
        return $cache[$value] = $value;
    }
    $name = isset($matches[2][0]) ? dvsModsFccUsableDmrName($matches[2][0], $callsign) : false;
    if ($name !== false) { dvsModsFccDmrNameCache($callsign, $name, true); }
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
    if ($result === '---') {
        $dmrName = dvsModsFccDmrName($callsign);
        if ($dmrName !== false) { $result = $dmrName; }
    }
    return $cache[$callsign] = $result;
}
?>
