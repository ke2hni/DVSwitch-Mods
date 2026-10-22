<?php
// Version: 1.0.0
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

// Normalize only the private lookup copy. The dashboard continues to display
// the original transmitted value. Replacement characters are common when a
// gateway appends an unsupported symbol to an otherwise valid callsign.
function dvsModsNormalizeLookupCallsign($rawCallsign) {
    $callsign = strtoupper(trim((string)$rawCallsign));
    $callsign = preg_replace('/\x{FFFD}+/u', '', $callsign);
    if (!is_string($callsign)) { return ''; }
    $slash = strpos($callsign, '/');
    if ($slash !== false) { $callsign = substr($callsign, 0, $slash); }
    $callsign = trim($callsign);
    // D-Star commonly supplies a module after a space (for example N4KF Z).
    // Keep a valid callsign token and discard only that module; ordinary
    // embedded callsign spaces such as W D 1 V are still compacted below.
    $tokens = preg_split('/[[:space:]]+/u', $callsign, -1, PREG_SPLIT_NO_EMPTY);
    if (is_array($tokens) && count($tokens) > 1 && preg_match('/^(?=.*[A-Z])(?=.*[0-9])[A-Z0-9]{3,10}$/D', $tokens[0])) {
        $callsign = $tokens[0];
    } else {
        $callsign = preg_replace('/[[:space:]]+/u', '', $callsign);
    }
    $dash = strpos($callsign, '-');
    if ($dash !== false) { $callsign = substr($callsign, 0, $dash); }
    return $callsign;
}

function dvsModsFccDmrName($rawCallsign) {
    static $cache = array();
    $callsign = dvsModsNormalizeLookupCallsign($rawCallsign);
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

function dvsModsNxdnIdCallsign($rawCallsign, $databasePath = '/var/lib/mmdvm/NXDN.csv') {
    static $cache = array();
    $value = trim((string)$rawCallsign);
    if (!preg_match('/^[0-9]{1,5}$/D', $value)) { return $value; }
    if (array_key_exists($value, $cache)) { return $cache[$value]; }
    if (!is_readable($databasePath)) { return $cache[$value] = $value; }
    $handle = @fopen($databasePath, 'r');
    if ($handle === false) { return $cache[$value] = $value; }
    $callsign = false;
    while (($row = fgetcsv($handle)) !== false) {
        if (!isset($row[0], $row[1])) { continue; }
        $id = trim((string)$row[0]);
        $candidate = strtoupper(trim((string)$row[1]));
        if ($id !== $value || !preg_match('/^(?=.*[A-Z])(?=.*[0-9])[A-Z0-9]{3,10}$/D', $candidate)) { continue; }
        if ($callsign !== false && $callsign !== $candidate) { fclose($handle); return $cache[$value] = $value; }
        $callsign = $candidate;
    }
    fclose($handle);
    return $cache[$value] = ($callsign !== false ? $callsign : $value);
}

function dvsModsFccFirstName($rawCallsign) {
    static $cache = array();
    $callsign = dvsModsNormalizeLookupCallsign($rawCallsign);
    if (!preg_match('/^[A-Z0-9]{3,10}$/', $callsign)) { return '---'; }
    if (isset($cache[$callsign])) { return $cache[$callsign]; }

    global $dvsModsFccFirstNamesPath;
    $path = isset($dvsModsFccFirstNamesPath) && is_string($dvsModsFccFirstNamesPath)
        ? $dvsModsFccFirstNamesPath : '/var/lib/mmdvm/dvswitch-mods-fcc-first-names.dat';
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

/** Return a user-defined display label for a callsign without a data name. */
function dvsModsCustomCallsignDescription($rawCallsign) {
    static $descriptions = null;
    if ($descriptions === null) {
        $descriptions = array();
        global $dvsModsCustomCallsignDescriptionPath;
        $path = isset($dvsModsCustomCallsignDescriptionPath) && is_string($dvsModsCustomCallsignDescriptionPath)
            ? $dvsModsCustomCallsignDescriptionPath : '/etc/dvswitch-mods/callsign-descriptions.tsv';
        if (is_readable($path)) {
            $handle = @fopen($path, 'rb');
            if ($handle !== false) {
                while (($line = fgets($handle)) !== false) {
                    $line = trim($line);
                    if ($line === '' || $line[0] === '#') { continue; }
                    $separator = strpos($line, "\t");
                    if ($separator === false) { $separator = strpos($line, '='); }
                    if ($separator === false) { continue; }
                    $callsign = strtoupper(trim(substr($line, 0, $separator)));
                    $description = trim(substr($line, $separator + 1));
                    if (!preg_match('/^[A-Z0-9]+(?:-[A-Z0-9]+)*$/D', $callsign) || strlen($callsign) > 16 || $description === '' || strlen($description) > 80 || preg_match('/[\x00-\x1F\x7F]/', $description)) { continue; }
                    $descriptions[$callsign] = $description;
                }
                fclose($handle);
            }
        }
    }
    $callsign = strtoupper(trim((string)$rawCallsign));
    return array_key_exists($callsign, $descriptions) ? $descriptions[$callsign] : false;
}

/** Return a user-entered fallback name for a callsign without an FCC/DMR name. */
function dvsModsManualCallsignName($rawCallsign) {
    static $names = null;
    if ($names === null) {
        $names = array();
        global $dvsModsManualCallsignNamesPath;
        $path = isset($dvsModsManualCallsignNamesPath) && is_string($dvsModsManualCallsignNamesPath)
            ? $dvsModsManualCallsignNamesPath : '/etc/dvswitch-mods/callsign-lookup.tsv';
        if (is_readable($path) && ($handle = @fopen($path, 'rb')) !== false) {
            while (($line = fgets($handle)) !== false) {
                $line = trim($line);
                if ($line === '' || $line[0] === '#') { continue; }
                $separator = strpos($line, '=');
                if ($separator === false) { $separator = strpos($line, "\t"); }
                if ($separator === false) { continue; }
                $callsign = dvsModsNormalizeLookupCallsign(substr($line, 0, $separator));
                $name = trim(substr($line, $separator + 1));
                if (!preg_match('/^(?=.*[A-Z])(?=.*[0-9])[A-Z0-9]{3,10}$/D', $callsign) || $name === '' || strlen($name) > 100 || preg_match('/[\x00-\x1F\x7F]/', $name)) { continue; }
                $names[$callsign] = $name;
            }
            fclose($handle);
        }
    }
    $callsign = dvsModsNormalizeLookupCallsign($rawCallsign);
    return array_key_exists($callsign, $names) ? $names[$callsign] : false;
}

/** Save a manually entered name only while the FCC/DMR database has no name. */
function dvsModsSaveManualCallsignName($rawCallsign, $rawName, $path = '/etc/dvswitch-mods/callsign-lookup.tsv') {
    $callsign = dvsModsNormalizeLookupCallsign($rawCallsign);
    $name = trim((string)$rawName);
    if (!preg_match('/^(?=.*[A-Z])(?=.*[0-9])[A-Z0-9]{3,10}$/D', $callsign)) { return 'Invalid callsign.'; }
    if ($name === '' || strlen($name) > 100 || preg_match('/[\x00-\x1F\x7F=]/', $name)) { return 'Enter a name of 1 to 100 characters without tabs or line breaks.'; }
    if (dvsModsFccFirstName($callsign) !== '---') { return 'A name is already available in the local FCC/DMR databases.'; }
    if (dvsModsCustomCallsignDescription($callsign) !== false) { return 'A custom description is already available for this callsign.'; }
    $handle = @fopen($path, 'c+');
    if ($handle === false) { return 'The local callsign names file is unavailable.'; }
    if (!flock($handle, LOCK_EX)) { fclose($handle); return 'Could not lock the local callsign names file.'; }
    rewind($handle);
    $preserved = array();
    $entries = array();
    while (($line = fgets($handle)) !== false) {
        $trimmed = trim($line);
        $separator = strpos($trimmed, '=');
        if ($separator === false) { $separator = strpos($trimmed, "\t"); }
        $existing = $separator !== false ? dvsModsNormalizeLookupCallsign(substr($trimmed, 0, $separator)) : '';
        if ($trimmed !== '' && $trimmed[0] !== '#' && preg_match('/^(?=.*[A-Z])(?=.*[0-9])[A-Z0-9]{3,10}$/D', $existing)) {
            if ($existing !== $callsign) { $entries[] = array($existing, rtrim($line, "\r\n")); }
            continue;
        }
        $preserved[] = rtrim($line, "\r\n");
    }
    $entries[] = array($callsign, $callsign.' = '.$name);
    usort($entries, function ($left, $right) { return strcmp($left[0], $right[0]); });
    $lines = array_merge($preserved, array_map(function ($entry) { return $entry[1]; }, $entries));
    $contents = implode("\n", $lines)."\n";
    rewind($handle);
    $written = ftruncate($handle, 0) && fwrite($handle, $contents) === strlen($contents) && fflush($handle);
    flock($handle, LOCK_UN);
    fclose($handle);
    return $written ? true : 'Could not save the local callsign name.';
}

/** Save a user-defined display description for an identifier without FCC/DMR data. */
function dvsModsSaveCustomCallsignDescription($rawCallsign, $rawDescription, $path = '/etc/dvswitch-mods/callsign-descriptions.tsv') {
    $callsign = strtoupper(trim((string)$rawCallsign));
    $description = trim((string)$rawDescription);
    if (!preg_match('/^[A-Z0-9]+(?:-[A-Z0-9]+)*$/D', $callsign) || strlen($callsign) > 16) { return 'Invalid callsign or identifier.'; }
    if ($description === '' || strlen($description) > 80 || preg_match('/[\x00-\x1F\x7F=]/', $description)) {
        return 'Enter a description of 1 to 80 characters without tabs, line breaks, or equals signs.';
    }
    // Only check FCC/DMR when the exact displayed identifier is a callsign.
    // A suffix such as AL-LINK is a dashboard/custom identifier, not AL.
    if (preg_match('/^(?=.*[A-Z])(?=.*[0-9])[A-Z0-9]{3,10}$/D', $callsign)
        && dvsModsFccFirstName($callsign) !== '---') {
        return 'A name is already available in the local FCC/DMR databases.';
    }
    $handle = @fopen($path, 'c+');
    if ($handle === false) { return 'The local callsign descriptions file is unavailable.'; }
    if (!flock($handle, LOCK_EX)) { fclose($handle); return 'Could not lock the local callsign descriptions file.'; }
    rewind($handle);
    $lines = array();
    while (($line = fgets($handle)) !== false) {
        $trimmed = trim($line);
        $separator = strpos($trimmed, '=');
        if ($separator === false) { $separator = strpos($trimmed, "\t"); }
        if ($trimmed !== '' && $trimmed[0] !== '#' && $separator !== false
            && strtoupper(trim(substr($trimmed, 0, $separator))) === $callsign) { continue; }
        $lines[] = rtrim($line, "\r\n");
    }
    $lines[] = $callsign.' = '.$description;
    $contents = implode("\n", $lines)."\n";
    rewind($handle);
    $written = ftruncate($handle, 0) && fwrite($handle, $contents) === strlen($contents) && fflush($handle);
    flock($handle, LOCK_UN);
    fclose($handle);
    return $written ? true : 'Could not save the local callsign description.';
}

/** Resolve a callsign to its CTY.DAT DXCC entity, including prefix exceptions. */
function dvsModsFccCountry($rawCallsign) {
    static $prefixes = null;
    static $cache = array();
    $callsign = strtoupper(trim((string)$rawCallsign));
    $callsign = preg_replace('/[^A-Z0-9\/]/', '', $callsign);
    if (!preg_match('/^[A-Z0-9]{3,10}(?:\/[A-Z0-9]{1,10})*$/D', $callsign)) { return ''; }
    $callsign = preg_replace('/\/[A-Z]$/', '', $callsign);
    if (isset($cache[$callsign])) { return $cache[$callsign]; }
    global $dvsModsFccCountryDatabasePath;
    $path = isset($dvsModsFccCountryDatabasePath) && is_string($dvsModsFccCountryDatabasePath)
        ? $dvsModsFccCountryDatabasePath : '/var/lib/mmdvm/dvswitch-mods-cty.dat';
    if (!is_readable($path)) { return $cache[$callsign] = ''; }
    if ($prefixes === null) {
        $prefixes = array();
        $contents = @file_get_contents($path);
        if (!is_string($contents) || strpos($contents, 'AD1C') === false || strpos($contents, 'Argentina:') === false) { return $cache[$callsign] = ''; }
        $current = '';
        foreach (preg_split('/\r?\n/', $contents) as $line) {
            if (strpos($line, ':') !== false && preg_match('/^([^:;]+):/', $line, $header)) {
                $current = trim($header[1]);
                $line = substr($line, strlen($header[0]));
            }
            if ($current === '') { continue; }
            $line = strtoupper(trim(preg_replace('/\\s*#.*/', '', $line)));
            $line = preg_replace('/\\s+/', '', $line);
            if (strpos($line, ';') === false) { $line = rtrim($line, ','); }
            foreach (explode(',', $line) as $entry) {
                $entry = trim($entry);
                if ($entry === '') { continue; }
                $entry = rtrim($entry, ';');
                $exact = false;
                if (strpos($entry, '=') === 0) { $exact = true; $entry = substr($entry, 1); }
                $entry = preg_replace('/\\([^)]*\\)/', '', $entry);
                $rangePattern = '';
                if (preg_match('/^([A-Z0-9]+)\\[([A-Z0-9]*)\\]$/', $entry, $range)) {
                    $entry = $range[1];
                    $letters = preg_split('//', $range[2], -1, PREG_SPLIT_NO_EMPTY);
                    $rangePattern = '^'.preg_quote($range[1], '/').'(?:['.preg_quote(implode('', $letters), '/').']|(?=[0-9]))';
                } elseif (preg_match('/^([A-Z0-9]+)-([A-Z0-9]+)$/', $entry, $range)) {
                    $left = $range[1];
                    $right = $range[2];
                    $common = 0;
                    $limit = min(strlen($left), strlen($right));
                    while ($common < $limit && $left[$common] === $right[$common]) { $common++; }
                    if ($common > 0 && strlen($left) === $common + 1 && strlen($right) === $common + 1 && ord($left[$common]) <= ord($right[$common])) {
                        $entry = substr($left, 0, $common);
                        $rangePattern = '^'.preg_quote($entry, '/').'['.$left[$common].'-'.$right[$common].']';
                    }
                }
                if (!preg_match('/^[A-Z0-9]+$/', $entry)) { continue; }
                $type = $exact ? 'exact' : ($rangePattern !== '' ? 'range' : 'prefix');
                $value = $exact ? $entry : ($rangePattern !== '' ? $rangePattern : $entry);
                $prefixes[] = array($type, $value, $current, strlen($entry));
            }
        }
        usort($prefixes, function ($a, $b) {
            if ($a[3] !== $b[3]) { return $b[3] <=> $a[3]; }
            $priority = array('exact' => 3, 'range' => 2, 'prefix' => 1);
            return $priority[$b[0]] <=> $priority[$a[0]];
        });
    }
    if (!$prefixes) { return $cache[$callsign] = ''; }
    $candidates = explode('/', $callsign);
    foreach (array_reverse($candidates) as $candidate) {
        foreach ($prefixes as $entry) {
            if ($entry[0] === 'exact' && $candidate === $entry[1]) { return $cache[$callsign] = $entry[2]; }
            if ($entry[0] === 'range' && preg_match('/'.$entry[1].'/', $candidate)) { return $cache[$callsign] = $entry[2]; }
            if ($entry[0] === 'prefix' && strpos($candidate, $entry[1]) === 0) { return $cache[$callsign] = $entry[2]; }
        }
    }
    return $cache[$callsign] = '';
}
?>
