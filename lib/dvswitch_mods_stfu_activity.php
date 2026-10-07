<?php
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jeff Milne, KE2HNI
// DVSwitch-Mods: STFU activity feed v4

/** Parse recent STFU ODMR traffic into DVSwitch's activity-row structure. */
function dvsModsStfuActivityRows($paths = null)
{
    if ($paths === null) {
        $paths = array('/var/log/dvswitch/STFU.log');
        foreach (array('/var/log/dvswitch/STFU.log.1', '/var/log/dvswitch/STFU-previous.log') as $path) {
            if (is_file($path)) { $paths[] = $path; }
        }
    }
    $events = array();
    $open = array();
    $sequence = 0;
    foreach ($paths as $path) {
        if (!is_readable($path) || is_link($path)) { continue; }
        $handle = @fopen($path, 'rb');
        if ($handle === false) { continue; }
        $size = @filesize($path);
        if (is_int($size) && $size > 524288) {
            @fseek($handle, $size - 524288);
            @fgets($handle); // discard a possibly partial first record
        }
        $lines = array();
        while (($line = fgets($handle)) !== false) {
            $line = trim($line);
            if ($line !== '') { $lines[] = $line; }
        }
        fclose($handle);
        if (count($lines) > 2000) { $lines = array_slice($lines, -2000); }
        foreach ($lines as $line) {
            if (!preg_match('/^[A-Z]: (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}) (.*)$/', $line, $match)) { continue; }
            $message = $match[2];
            if (preg_match('/^DMR, ODMR Begin (Tx|Rx):\s*src\s*=\s*([0-9]+),\s*dst\s*=\s*([0-9]+)\s*\((GROUP|PRIVATE)\)/i', $message, $call)) {
                $direction = strtoupper($call[1]);
                $row = array($match[1], 'STFU', $call[2], '', 'TG '.$call[3], $direction === 'TX' ? 'Net' : 'LNet', null, '', '', '', '');
                $events[] = array('row' => $row, 'direction' => $direction, 'sequence' => $sequence++);
                $open[$direction] = count($events) - 1;
                continue;
            }
            if (preg_match('/^DMR, ODMR End (Tx|Rx):.*?frame count was\s+([0-9]+)\s+frames/i', $message, $end)) {
                $direction = strtoupper($end[1]);
                if (isset($open[$direction], $events[$open[$direction]])) {
                    $index = $open[$direction];
                    $events[$index]['row'][6] = number_format(((int)$end[2]) * 0.059, 1, '.', '');
                    unset($open[$direction]);
                }
            }
        }
    }
    usort($events, function ($left, $right) {
        $time = strcmp($right['row'][0], $left['row'][0]);
        return $time !== 0 ? $time : ($right['sequence'] <=> $left['sequence']);
    });
    return array_map(function ($event) { return $event['row']; }, $events);
}

/** Merge STFU events with MMDVM events without changing historical timestamps. */
function dvsModsStfuMergeActivity($rows, $paths = null)
{
    $rows = is_array($rows) ? $rows : array();
    $rows = array_merge($rows, dvsModsStfuActivityRows($paths));
    usort($rows, function ($left, $right) {
        $time = strcmp((string)($right[0] ?? ''), (string)($left[0] ?? ''));
        return $time !== 0 ? $time : 0;
    });
    return $rows;
}

/** Look up an STFU destination using the node's BrandMeister talkgroup list. */
function dvsModsStfuTargetDisplay($rawTarget, $listPath = null)
{
    $target = trim((string)$rawTarget);
    if (!preg_match('/^TG\s+([0-9]+)$/iD', $target, $match)) { return $target; }
    $number = $match[1];
    $names = array();
    if ($listPath === null) { $listPath = '/var/lib/mmdvm/TGList_BM.txt'; }
    foreach ((array)$listPath as $path) {
        if (!is_readable($path)) { continue; }
        foreach ((array)file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
            if ($line === '' || $line[0] === '#') { continue; }
            $fields = explode(';', $line, 4);
            if (count($fields) !== 4 || trim($fields[0]) !== $number || trim($fields[1]) !== '0') { continue; }
            $name = preg_replace('/\s+/u', ' ', str_replace('_', ' ', trim($fields[2])));
            if (is_string($name) && $name !== '') { $names[strtolower($name)] = $name; }
        }
    }
    $label = count($names) === 1 ? reset($names) : 'TG '.$number;
    return $label.' (TG '.$number.')';
}

/** Render an STFU status card separately from the BM/TGIF DMR Master card. */
function dvsModsStfuRenderCard($abinfo, $lastHeard, $logPaths = null, $listPath = null)
{
    $latest = null;
    foreach (dvsModsStfuActivityRows($logPaths) as $row) {
        if (isset($row[1], $row[5]) && $row[1] === 'STFU' && $row[5] === 'Net') { $latest = $row; break; }
    }
    // In STFU mode, show the selected target from the live bridge status.
    // Activity rows remain sourced from STFU.log, so tuning alone does not
    // create an RX event or alter historical activity.
    $liveMode = isset($abinfo['tlv']['ambe_mode']) ? strtoupper(trim((string)$abinfo['tlv']['ambe_mode'])) : '';
    if ($liveMode === 'STFU' && isset($abinfo['last_tune'])) {
        $tune = trim((string)$abinfo['last_tune']);
        if (preg_match('/^(?:TG\\s*)?([0-9]+)$/iD', $tune, $match) && $match[1] !== '0') {
            if ($latest === null) { $latest = array('', 'STFU', '', '', '', 'Net'); }
            $latest[4] = 'TG '.$match[1];
        }
    }
    echo "<br /><table>\n<tr><th colspan=\"2\">STFU Net</th></tr>\n";
    if (function_exists('isProcessRunning') && isProcessRunning('STFU')) {
        echo '<tr><td style="background:#ffffed;text-align:center;" colspan="2">';
        if ($latest !== null) {
            $label = dvsModsStfuTargetDisplay($latest[4], $listPath);
            if (preg_match('/^(.*?)\s+\((TG\s+[0-9]+)\)$/iD', $label, $parts)) {
                echo 'Room<br/><span style="color:#b5651d;font-weight:bold;white-space:normal;word-break:normal;overflow-wrap:anywhere;">'.htmlspecialchars($parts[1], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8').'</span>';
                if (strcasecmp($parts[1], $parts[2]) !== 0) {
                    echo '<br/><span style="color:#b5651d;font-weight:bold;white-space:normal;word-break:normal;overflow-wrap:anywhere;">('.htmlspecialchars($parts[2], ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8').')</span>';
                }
            } else {
                echo 'Room<br/><span style="color:#b5651d;font-weight:bold;white-space:normal;word-break:normal;overflow-wrap:anywhere;">'.htmlspecialchars($label, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8').'</span>';
            }
        } else {
            echo '<span style="color:#b5651d;font-weight:bold;">Listening</span>';
        }
        echo "</td></tr>\n";
    } else {
        echo "<tr><td colspan=\"2\" style=\"background:#ffffed;color:#b0b0b0;font-weight:bold\">OFFLINE</td></tr>\n";
    }
    echo "</table>\n";
}
?>
