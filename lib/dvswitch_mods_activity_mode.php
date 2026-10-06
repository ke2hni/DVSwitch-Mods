<?php
// DVSwitch-Mods: dashboard activity network labels helper v3
// SPDX-License-Identifier: MIT

/** Return the latest mode transition at or before a UTC activity timestamp. */
function dvsModsActivityTransitionAt($utcTimestamp, $historyFile, $allowedModes = null)
{
    $utcTimestamp = (string)$utcTimestamp;
    $event = DateTimeImmutable::createFromFormat('!Y-m-d H:i:s', $utcTimestamp, new DateTimeZone('UTC'));
    if ($event === false || $event->format('Y-m-d H:i:s') !== $utcTimestamp) { return null; }
    $eventAt = $event->getTimestamp();
    if (!is_file($historyFile) || !is_readable($historyFile)) { return null; }

    $active = null;
    $activeAt = null;
    $lines = @file($historyFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if (!is_array($lines)) { return null; }
    foreach ($lines as $line) {
        $fields = explode("\t", $line, 2);
        if (count($fields) !== 2 || !ctype_digit($fields[0])) { continue; }
        $historyMode = strtoupper(trim($fields[1]));
        $knownModes = array('BM', 'TGIF', 'STFU', 'YSF', 'P25', 'NXDN', 'DSTAR');
        if (!in_array($historyMode, $allowedModes === null ? $knownModes : $allowedModes, true)) { continue; }
        $transitionAt = (int)$fields[0];
        if ($transitionAt <= $eventAt && ($activeAt === null || $transitionAt >= $activeAt)) {
            $active = array('at' => $transitionAt, 'mode' => $historyMode);
            $activeAt = $transitionAt;
        }
    }
    return $active;
}

/** Return only the mode for callers that do not need the transition time. */
function dvsModsActivityModeAt($utcTimestamp, $historyFile)
{
    $transition = dvsModsActivityTransitionAt($utcTimestamp, $historyFile);
    return $transition === null ? null : $transition['mode'];
}

/**
 * Preserve the mode label represented by each event timestamp. DMR network
 * DMR rows use the most recent BM/TGIF network selection at the event time.
 * Non-DMR mode changes do not replace that network label. Other modes and
 * older unknown rows retain their original dashboard label.
 */
function dvsModsActivityModeLabel($mode, $utcTimestamp, $stateFile = null, $historyFile = null)
{
    $mode = (string)$mode;
    if ($mode !== 'DMR' && !preg_match('/^DMR Slot [12]$/D', $mode)) { return $mode; }

    if ($historyFile === null) {
        $historyFile = '/var/lib/dvswitch-mods/activity-mode-history.tsv';
    }
    $event = DateTimeImmutable::createFromFormat('!Y-m-d H:i:s', (string)$utcTimestamp, new DateTimeZone('UTC'));
    if ($event === false || $event->format('Y-m-d H:i:s') !== (string)$utcTimestamp) { return $mode; }
    $eventAt = $event->getTimestamp();
    $transition = dvsModsActivityTransitionAt($utcTimestamp, $historyFile, array('BM', 'TGIF'));

    // Use live state for the short interval before systemd records a recent
    // BM/TGIF button selection. Non-DMR selections such as STFU must never
    // replace the last DMR network label. A newer network history event takes
    // precedence over stale current-mode state left from before reboot.
    if ($stateFile === null) { $stateFile = '/var/lib/dvswitch-mode-buttons/current-mode'; }
    if (is_file($stateFile) && is_readable($stateFile)) {
        $selectedMode = strtoupper(trim((string)file_get_contents($stateFile)));
        $selectedAt = @filemtime($stateFile);
        if ($selectedAt !== false && $eventAt >= $selectedAt) {
            if ($transition !== null && $transition['at'] > $selectedAt) {
                return $transition['mode'];
            }
            if (in_array($selectedMode, array('BM', 'TGIF'), true)) { return $selectedMode; }
        }
    }

    if ($transition !== null) { return $transition['mode']; }

    return $mode;
}
?>
