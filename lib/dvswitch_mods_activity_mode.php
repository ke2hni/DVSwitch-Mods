<?php
// DVSwitch-Mods: dashboard activity network labels helper v1
// SPDX-License-Identifier: MIT

/**
 * Display the selected DVSwitch DMR network for activity logged since the
 * most recent dashboard mode selection. Older rows retain their protocol
 * label because their network cannot be reconstructed from current state.
 */
function dvsModsActivityModeLabel($mode, $utcTimestamp, $stateFile = null)
{
    $mode = (string)$mode;
    if ($mode !== 'DMR' && !preg_match('/^DMR Slot [12]$/D', $mode)) { return $mode; }

    if ($stateFile === null) {
        $stateFile = '/var/lib/dvswitch-mode-buttons/current-mode';
    }
    if (!is_file($stateFile) || !is_readable($stateFile)) { return $mode; }

    $selectedMode = strtoupper(trim((string)file_get_contents($stateFile)));
    if (!in_array($selectedMode, array('BM', 'TGIF', 'STFU'), true)) { return $mode; }

    $selectedAt = @filemtime($stateFile);
    if ($selectedAt === false) { return $mode; }

    $utcTimestamp = (string)$utcTimestamp;
    $event = DateTimeImmutable::createFromFormat('!Y-m-d H:i:s', $utcTimestamp, new DateTimeZone('UTC'));
    if ($event === false || $event->format('Y-m-d H:i:s') !== $utcTimestamp) { return $mode; }
    $eventAt = $event->getTimestamp();
    if ($eventAt < $selectedAt) { return $mode; }

    return $selectedMode;
}
?>
