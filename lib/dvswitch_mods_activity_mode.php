<?php
// DVSwitch-Mods: dashboard activity network labels helper v2
// SPDX-License-Identifier: MIT

/** Return the selected mode that was active when a UTC activity row was logged. */
function dvsModsActivityModeAt($utcTimestamp, $historyFile)
{
    $utcTimestamp = (string)$utcTimestamp;
    $event = DateTimeImmutable::createFromFormat('!Y-m-d H:i:s', $utcTimestamp, new DateTimeZone('UTC'));
    if ($event === false || $event->format('Y-m-d H:i:s') !== $utcTimestamp) { return null; }
    $eventAt = $event->getTimestamp();
    if (!is_file($historyFile) || !is_readable($historyFile)) { return null; }

    $activeMode = null;
    $activeAt = null;
    $lines = @file($historyFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if (!is_array($lines)) { return null; }
    foreach ($lines as $line) {
        $fields = explode("\t", $line, 2);
        if (count($fields) !== 2 || !ctype_digit($fields[0])) { continue; }
        $historyMode = strtoupper(trim($fields[1]));
        if (!in_array($historyMode, array('BM', 'TGIF', 'STFU', 'YSF', 'P25', 'NXDN', 'DSTAR'), true)) { continue; }
        $transitionAt = (int)$fields[0];
        if ($transitionAt <= $eventAt && ($activeAt === null || $transitionAt >= $activeAt)) {
            $activeMode = $historyMode;
            $activeAt = $transitionAt;
        }
    }
    return $activeMode;
}

/**
 * Preserve the mode label represented by each event timestamp. DMR network
 * names are substituted only for rows whose timestamp falls inside a DMR
 * network selection interval; all other modes and older unknown rows retain
 * their original dashboard label.
 */
function dvsModsActivityModeLabel($mode, $utcTimestamp, $stateFile = null, $historyFile = null)
{
    $mode = (string)$mode;
    if ($mode !== 'DMR' && !preg_match('/^DMR Slot [12]$/D', $mode)) { return $mode; }

    if ($historyFile === null) {
        $historyFile = '/var/lib/dvswitch-mods/activity-mode-history.tsv';
    }
    // Use the live state for the newest interval, including the short window
    // before systemd has finished recording a just-written mode transition.
    if ($stateFile === null) { $stateFile = '/var/lib/dvswitch-mode-buttons/current-mode'; }
    if (is_file($stateFile) && is_readable($stateFile)) {
        $selectedMode = strtoupper(trim((string)file_get_contents($stateFile)));
        $selectedAt = @filemtime($stateFile);
        $event = DateTimeImmutable::createFromFormat('!Y-m-d H:i:s', (string)$utcTimestamp, new DateTimeZone('UTC'));
        if ($selectedAt !== false && $event !== false && $event->getTimestamp() >= $selectedAt) {
            return in_array($selectedMode, array('BM', 'TGIF', 'STFU'), true) ? $selectedMode : $mode;
        }
    }

    $modeAtEvent = dvsModsActivityModeAt($utcTimestamp, $historyFile);
    if (in_array($modeAtEvent, array('BM', 'TGIF', 'STFU'), true)) { return $modeAtEvent; }

    return $mode;
}
?>
