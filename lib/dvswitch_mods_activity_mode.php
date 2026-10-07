<?php
// DVSwitch-Mods: DMR network activity labels v1
// SPDX-License-Identifier: MIT

/** Convert a MMDVM_Bridge UTC timestamp (optionally with milliseconds) to epoch ms. */
function dvsModsActivityTimestampMs($timestamp)
{
    $timestamp = (string)$timestamp;
    if (!preg_match('/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?$/D', $timestamp, $match)) { return null; }
    $fraction = isset($match[2]) ? str_pad($match[2], 6, '0') : '000000';
    $date = DateTimeImmutable::createFromFormat('!Y-m-d H:i:s.u', $match[1].'.'.$fraction, new DateTimeZone('UTC'));
    if ($date === false) { return null; }
    $errors = DateTimeImmutable::getLastErrors();
    if (is_array($errors) && ($errors['warning_count'] !== 0 || $errors['error_count'] !== 0)) { return null; }
    if ($date->format('Y-m-d H:i:s') !== $match[1]) { return null; }
    return ((int)$date->format('U') * 1000) + intdiv((int)$date->format('u'), 1000);
}

/** Find the latest BM/TGIF selection at or before the activity event. */
function dvsModsDmrNetworkAt($timestamp, $historyFile = null)
{
    if ($historyFile === null) {
        $historyFile = getenv('DVS_DMR_NETWORK_HISTORY_FILE') ?: '/var/lib/dvswitch-mods/dmr-network-history.tsv';
    }
    $eventAt = dvsModsActivityTimestampMs($timestamp);
    if ($eventAt === null || !is_file($historyFile) || !is_readable($historyFile)) { return null; }
    $active = null;
    $activeAt = null;
    $lines = @file($historyFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if (!is_array($lines)) { return null; }
    foreach ($lines as $line) {
        $fields = explode("\t", $line, 2);
        if (count($fields) !== 2 || !ctype_digit($fields[0]) || !in_array($fields[1], array('BM', 'TGIF'), true)) { continue; }
        $transitionAt = (int)$fields[0];
        if ($transitionAt <= $eventAt && ($activeAt === null || $transitionAt >= $activeAt)) {
            $active = $fields[1];
            $activeAt = $transitionAt;
        }
    }
    return $active;
}

/** Relabel received DMR activity only; preserve every other DVSwitch label. */
function dvsModsActivityModeLabel($mode, $utcTimestamp, $source = 'Net', $historyFile = null)
{
    $mode = (string)$mode;
    if (!in_array($mode, array('DMR', 'DMR Slot 1', 'DMR Slot 2'), true) || $source !== 'Net') { return $mode; }
    $network = dvsModsDmrNetworkAt($utcTimestamp, $historyFile);
    return $network === null ? $mode : $network;
}
?>
