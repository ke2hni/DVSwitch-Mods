<?php
declare(strict_types=1);
header('Content-Type: application/json');
if ($_SERVER['REQUEST_METHOD'] !== 'POST') { http_response_code(405); echo json_encode(['ok'=>false]); exit; }
$mode = strtoupper((string)($_POST['mode'] ?? ''));
if (!in_array($mode, ['P25','YSF','NXDN','DSTAR','STFU'], true)) { http_response_code(400); echo json_encode(['ok'=>false]); exit; }
$cmd = '/usr/local/sbin/dvswitch-dashboard-mode ' . escapeshellarg($mode) . ' 2>&1';
$output = []; $status = 1; exec($cmd, $output, $status);
if ($status !== 0) { http_response_code(500); echo json_encode(['ok'=>false]); exit; }
echo json_encode(['ok'=>true,'mode'=>$mode]);
