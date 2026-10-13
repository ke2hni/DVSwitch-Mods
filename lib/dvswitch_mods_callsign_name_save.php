<?php
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Jeff Milne, KE2HNI

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function dvsModsCallsignNameSaveReply($status, $ok, $message) {
    http_response_code($status);
    echo json_encode(array('ok' => $ok, 'message' => $message));
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    dvsModsCallsignNameSaveReply(405, false, 'Use the dashboard name form to submit an entry.');
}

// Reject cross-origin form submissions. This dashboard endpoint is intended
// for the same browser origin that served the dashboard page.
$origin = isset($_SERVER['HTTP_ORIGIN']) ? parse_url($_SERVER['HTTP_ORIGIN']) : false;
$requestHost = strtolower((string)($_SERVER['HTTP_HOST'] ?? ''));
$originHost = is_array($origin) ? strtolower((string)($origin['host'] ?? '') . (isset($origin['port']) ? ':'.$origin['port'] : '')) : '';
if (!is_array($origin) || !in_array(($origin['scheme'] ?? ''), array('http', 'https'), true) || $requestHost === '' || $originHost !== $requestHost) {
    dvsModsCallsignNameSaveReply(403, false, 'The request did not come from this dashboard.');
}

require_once __DIR__.'/include/dvswitch_mods_fcc_first_names.php';
$type = $_POST['type'] ?? '1';
if ($type === '1') {
    $result = dvsModsSaveManualCallsignName($_POST['callsign'] ?? '', $_POST['name'] ?? '');
} elseif ($type === '2') {
    $result = dvsModsSaveCustomCallsignDescription($_POST['callsign'] ?? '', $_POST['name'] ?? '');
} else {
    dvsModsCallsignNameSaveReply(400, false, 'Choose an operator name or a custom description.');
}
if ($result !== true) { dvsModsCallsignNameSaveReply(400, false, $result); }
dvsModsCallsignNameSaveReply(200, true, $type === '1' ? 'Operator name saved.' : 'Custom description saved.');
?>
