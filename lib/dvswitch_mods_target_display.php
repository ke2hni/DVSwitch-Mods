<?php
// Version: 1.0.0
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jeff Milne, KE2HNI
// DVSwitch-Mods: activity Target display helper v4

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

/** Return the D-Star reflector linked at the timestamp of an activity row. */
function dvsModsTargetDstarRef($timestamp) {
    $eventTime = strtotime((string)$timestamp);
    if ($eventTime === false) { return ''; }
    static $historyCache = array();
    global $dvsModsTargetIrcDdbLogDirectory;
    $directory = isset($dvsModsTargetIrcDdbLogDirectory) ? rtrim((string)$dvsModsTargetIrcDdbLogDirectory, '/') : '/var/log/ircddbgateway';
    if (!isset($historyCache[$directory])) {
        $events = array();
        $sequence = 0;
        foreach ((array)glob($directory.'/ircDDBGateway-*.log') as $path) {
            if (!is_readable($path)) { continue; }
            foreach ((array)file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
                if (!preg_match('/^M:\\s+(\\d{4}-\\d\\d-\\d\\d \\d\\d:\\d\\d:\\d\\d):\\s+(.+?)\\s*$/', $line, $matches)) { continue; }
                $lineTime = strtotime($matches[1]);
                if ($lineTime === false) { continue; }
                $message = $matches[2];
                $target = null;
                $clearedTarget = '';
                if (preg_match('/^Remote control user has linked "[^"]+" to "([^"]+)"(?: with reconnect \\d+)?$/i', $message, $state)) {
                    $target = trim($state[1]);
                } else if (preg_match('/^Linking .+? to (.+?)\\s*$/i', $message, $state)) {
                    $target = trim($state[1]);
                } else if (preg_match('/^D-(?:Plus|Extra|CS) link to (.+?) established$/i', $message, $state)) {
                    $target = trim($state[1]);
                } else if (preg_match('/^Removing outgoing D-(?:Plus|Extra|CS) link .+?, (.+?)\\s*$/i', $message, $state)) {
                    $clearedTarget = trim($state[1]);
                } else if (preg_match('/^D-(?:Plus|Extra|CS) disconnect acknowledgement received from (.+?)\\s*$/i', $message, $state)) {
                    $clearedTarget = trim($state[1]);
                } else if (preg_match('/^D-(?:Plus|Extra|CS) link to (.+?) has failed$/i', $message, $state)) {
                    $clearedTarget = trim($state[1]);
                }
                if ($target !== null || $clearedTarget !== '') { $events[] = array($lineTime, $sequence++, $target, $clearedTarget); }
            }
        }
        usort($events, function ($left, $right) {
            if ($left[0] === $right[0]) { return $left[1] <=> $right[1]; }
            return $left[0] <=> $right[0];
        });
        $historyCache[$directory] = $events;
    }
    $linked = '';
    foreach ($historyCache[$directory] as $event) {
        if ($event[0] > $eventTime) { break; }
        if ($event[2] !== null) {
            $target = dvsModsTargetCleanLabel($event[2]);
            $linked = preg_match('/^(?:REF|DCS|XRF|XLX)[A-Z0-9]*\\s+[A-Z]$/iD', $target) ? strtoupper($target) : '';
        } else if ($linked !== '' && strcasecmp(dvsModsTargetCleanLabel($event[3]), $linked) === 0) {
            $linked = '';
        }
    }
    return $linked;
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

function dvsModsTargetYsfName($ref) {
    $ref = trim((string)$ref);
    if ($ref === '') { return ''; }
    $hosts = dvsModsTargetDataPath('YSFHosts.txt');
    if (!is_readable($hosts)) { return ''; }
    foreach ((array)file($hosts, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $fields = explode(';', $line);
        if (count($fields) < 2 || trim($fields[0]) !== $ref) { continue; }
        $name = dvsModsTargetCleanLabel($fields[1]);
        if ($name !== '') { return $name; }
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
        $name = dvsModsTargetYsfName($ref);
        return $cache[$key] = dvsModsTargetWithType($name === '' ? $target : $name, 'TG', $ref);
    }

    if ($mode === 'D-Star') {
        if (preg_match('/^CQCQCQ(?:\s+via\s+([A-Z0-9]+)\s+([A-Z]))?$/iD', $target, $matches)) {
            $label = isset($matches[1]) ? strtoupper($matches[1].' '.$matches[2]) : '';
            if ($label === '') { $label = dvsModsTargetDstarRef($timestamp); }
            return $cache[$key] = ($label === '' ? 'General Call' : $label);
        }
        return $cache[$key] = $target;
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
        return $cache[$key] = ($label === '' ? 'TG '.$number : dvsModsTargetWithType($label, 'TG', $number));
    }

    return $cache[$key] = dvsModsTargetWithType($target);
}
?>
