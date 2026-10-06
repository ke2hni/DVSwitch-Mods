<?php
// DVSwitch-Mods: dashboard activity network labels helper v3
// SPDX-License-Identifier: MIT

/** Return the operating-system timezone used for DVSwitch activity timestamps. */
function dvsModsActivityTimezone()
{
    static $timezone = null;
    if ($timezone instanceof DateTimeZone) { return $timezone; }

    $systemTimezone = @file_get_contents('/etc/timezone');
    if (is_string($systemTimezone) && trim($systemTimezone) !== '') {
        $systemTimezone = ltrim(trim($systemTimezone), '/');
        try {
            $timezone = new DateTimeZone($systemTimezone);
            return $timezone;
        } catch (Exception $exception) {
            // Fall back to the /etc/localtime link or PHP's configured timezone.
        }
    }

    $localtime = @readlink('/etc/localtime');
    if (is_string($localtime) && preg_match('~/zoneinfo/(.+)$~', $localtime, $matches)) {
        try {
            $timezone = new DateTimeZone($matches[1]);
            return $timezone;
        } catch (Exception $exception) {
            // Fall back to PHP's configured timezone.
        }
    }

    $timezone = new DateTimeZone(date_default_timezone_get());
    return $timezone;
}

/** Return the latest mode transition at or before a dashboard activity timestamp. */
function dvsModsActivityTransitionAt($dashboardTimestamp, $historyFile, $allowedModes = null)
{
    $dashboardTimestamp = (string)$dashboardTimestamp;
    // PHP's configured timezone may differ from the operating-system timezone.
    $event = DateTimeImmutable::createFromFormat('!Y-m-d H:i:s', $dashboardTimestamp, dvsModsActivityTimezone());
    if ($event === false || $event->format('Y-m-d H:i:s') !== $dashboardTimestamp) { return null; }
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
function dvsModsActivityModeAt($dashboardTimestamp, $historyFile)
{
    $transition = dvsModsActivityTransitionAt($dashboardTimestamp, $historyFile);
    return $transition === null ? null : $transition['mode'];
}

/**
 * Preserve the mode label represented by each event timestamp. DMR network
 * DMR rows use the most recent BM/TGIF network selection at the event time.
 * Non-DMR mode changes do not replace that network label. Other modes and
 * older unknown rows retain their original dashboard label.
 */
function dvsModsActivityModeLabel($mode, $dashboardTimestamp, $stateFile = null, $historyFile = null)
{
    $mode = (string)$mode;
    if ($mode !== 'DMR' && !preg_match('/^DMR Slot [12]$/D', $mode)) { return $mode; }

    if ($historyFile === null) {
        $historyFile = '/var/lib/dvswitch-mods/activity-mode-history.tsv';
    }
    $dashboardTimestamp = (string)$dashboardTimestamp;
    $event = DateTimeImmutable::createFromFormat('!Y-m-d H:i:s', $dashboardTimestamp, dvsModsActivityTimezone());
    if ($event === false || $event->format('Y-m-d H:i:s') !== $dashboardTimestamp) { return $mode; }
    $eventAt = $event->getTimestamp();
    $transition = dvsModsActivityTransitionAt($dashboardTimestamp, $historyFile, array('BM', 'TGIF'));

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
