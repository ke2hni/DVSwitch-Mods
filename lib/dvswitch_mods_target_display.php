<?php
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jeff Milne, KE2HNI
// DVSwitch-Mods: activity Target display helper v2

function dvsModsTargetCleanLabel($value) {
    $value = preg_replace('/\s+/u', ' ', str_replace('_', ' ', trim((string)$value)));
    return is_string($value) ? $value : '';
}

function dvsModsTargetDataPath($name) {
    global $dvsModsTargetDataDirectory;
    $directory = isset($dvsModsTargetDataDirectory) ? rtrim((string)$dvsModsTargetDataDirectory, '/') : '/var/lib/mmdvm';
    return $directory.'/'.$name;
}

function dvsModsTargetJsonName($mode, $number) {
    $path = dvsModsTargetDataPath($mode.'Hosts.json');
    if (!is_readable($path)) { return ''; }
    $json = json_decode(file_get_contents($path), true);
    if (!isset($json['reflectors']) || !is_array($json['reflectors'])) { return ''; }
    foreach ($json['reflectors'] as $row) {
        if (!is_array($row) || !isset($row['designator']) || (string)$row['designator'] !== (string)$number) { continue; }
        foreach (array('name', 'sponsor') as $field) {
            if (!isset($row[$field]) || !is_string($row[$field])) { continue; }
            $label = dvsModsTargetCleanLabel($row[$field]);
            if ($label !== '' && strcasecmp($label, 'Place holder') !== 0) { return $label; }
        }
        return '';
    }
    return '';
}

function dvsModsTargetDmrNames($number) {
    $names = array();
    foreach (array(dvsModsTargetDataPath('TGList_BM.txt'), dvsModsTargetDataPath('TGList_TGIF.txt')) as $path) {
        if (!is_readable($path)) { continue; }
        $lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        if (!is_array($lines)) { continue; }
        foreach ($lines as $line) {
            if ($line === '' || $line[0] === '#') { continue; }
            $fields = explode(';', $line, 4);
            if (count($fields) !== 4 || trim($fields[0]) !== (string)$number || trim($fields[1]) !== '0') { continue; }
            $label = dvsModsTargetCleanLabel($fields[2]);
            if ($label !== '') { $names[strtolower($label)] = $label; }
        }
    }
    return array_values($names);
}

function dvsModsTargetWithType($label, $type = '', $value = '') {
    $label = dvsModsTargetCleanLabel($label);
    $value = dvsModsTargetCleanLabel($value);
    if ($type !== '' && $value !== '') { return ($label === '' ? 'Unknown' : $label).' ('.$type.' '.$value.')'; }
    return $label === '' ? 'Unknown' : $label;
}

function dvsModsTargetRefValue($target) {
    if (preg_match('/\b(?:REF|DCS|XRF|YSF)[-_ ]?([0-9]{3,5})\b/i', $target, $matches)) {
        return $matches[1];
    }
    if (preg_match('/\b([0-9]{3,5})\b/D', $target, $matches)) {
        return $matches[1];
    }
    return '';
}

function dvsModsTargetYsfRef($timestamp) {
    $eventTime = strtotime((string)$timestamp);
    if ($eventTime === false) { return ''; }
    $linked = '';
    $linkedTime = -1;
    foreach ((array)glob('/var/log/mmdvm/YSFGateway-*.log') as $path) {
        if (!is_readable($path)) { continue; }
        foreach ((array)file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
            if (!preg_match('/^\S+:\s+(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+) Linked to (.+?)\s*$/', $line, $matches)) { continue; }
            $lineTime = strtotime($matches[1]);
            if ($lineTime !== false && $lineTime <= $eventTime && $lineTime >= $linkedTime) {
                $linked = trim($matches[2]);
                $linkedTime = $lineTime;
            }
        }
    }
    if ($linked === '') { return ''; }
    $hosts = dvsModsTargetDataPath('YSFHosts.txt');
    if (!is_readable($hosts)) { return ''; }
    foreach ((array)file($hosts, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $fields = explode(';', $line);
        if (count($fields) >= 2 && strcasecmp(trim($fields[1]), $linked) === 0) { return trim($fields[0]); }
    }
    return '';
}

function dvsModsTargetDisplay($mode, $rawTarget, $activityType = '', $timestamp = '') {
    static $cache = array();
    $mode = trim((string)$mode);
    $target = dvsModsTargetCleanLabel($rawTarget);
    $activityType = trim((string)$activityType);
    $key = $mode."\0".$target."\0".$activityType."\0".(string)$timestamp;
    if (isset($cache[$key])) { return $cache[$key]; }

    if ($mode === 'YSF') {
        $ref = dvsModsTargetYsfRef($timestamp);
        if ($ref === '') { $ref = dvsModsTargetRefValue($target); }
        if (strcasecmp($activityType, 'GPS') === 0 || preg_match('/^\*+/D', $target)) {
            return $cache[$key] = dvsModsTargetWithType('GPS/Data', 'Ref', $ref);
        }
        return $cache[$key] = dvsModsTargetWithType('Group Call', 'Ref', $ref);
    }

    if ($mode === 'D-Star') {
        if (preg_match('/^CQCQCQ(?:\s+via\s+([A-Z0-9]+)\s+([A-Z]))?$/iD', $target, $matches)) {
            $label = isset($matches[1]) ? strtoupper($matches[1].' '.$matches[2]) : '';
            $ref = $label === '' ? '' : dvsModsTargetRefValue($label);
            return $cache[$key] = dvsModsTargetWithType($label === '' ? 'General Call' : $label, 'Ref', $ref);
        }
        $ref = dvsModsTargetRefValue($target);
        return $cache[$key] = dvsModsTargetWithType($target, 'Ref', $ref);
    }

    if (preg_match('/^TG\s+([0-9]+)$/iD', $target, $matches)) {
        $number = $matches[1];
        $label = '';
        if ($mode === 'P25' || $mode === 'NXDN') {
            $label = dvsModsTargetJsonName($mode, $number);
        } else if ($mode === 'DMR' || strpos($mode, 'DMR Slot ') === 0) {
            $names = dvsModsTargetDmrNames($number);
            if (count($names) === 1) { $label = $names[0]; }
        }
        return $cache[$key] = dvsModsTargetWithType($label === '' ? 'TG '.$number : $label, 'TG', $number);
    }

    return $cache[$key] = dvsModsTargetWithType($target);
}
?>
