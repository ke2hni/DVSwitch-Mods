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

function dvsModsTargetDisplay($mode, $rawTarget, $activityType = '') {
    static $cache = array();
    $mode = trim((string)$mode);
    $target = dvsModsTargetCleanLabel($rawTarget);
    $activityType = trim((string)$activityType);
    $key = $mode."\0".$target."\0".$activityType;
    if (isset($cache[$key])) { return $cache[$key]; }

    if ($mode === 'YSF') {
        if (strcasecmp($activityType, 'GPS') === 0 || preg_match('/^\*+/D', $target)) {
            return $cache[$key] = 'GPS/Data';
        }
        return $cache[$key] = 'Group Call';
    }

    if ($mode === 'D-Star') {
        if (preg_match('/^CQCQCQ(?:\s+via\s+([A-Z0-9]+)\s+([A-Z]))?$/iD', $target, $matches)) {
            return $cache[$key] = isset($matches[1]) ? strtoupper($matches[1].' '.$matches[2]) : 'General Call';
        }
        return $cache[$key] = ($target !== '' ? $target : 'Unknown');
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
        return $cache[$key] = ($label === '' ? 'TG '.$number : $label.' (TG '.$number.')');
    }

    return $cache[$key] = ($target !== '' ? $target : 'Unknown');
}
?>
