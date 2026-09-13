<?php
declare(strict_types=1);
header('Content-Type: application/json');
if ($_SERVER['REQUEST_METHOD'] !== 'POST') { http_response_code(405); echo json_encode(['ok'=>false]); exit; }
$network = strtolower((string)($_POST['network'] ?? ''));
if (!in_array($network, ['bm','tgif'], true)) { http_response_code(400); echo json_encode(['ok'=>false]); exit; }
$cmd = 'sudo -n /usr/local/sbin/dvswitch-dashboard-dmr-network ' . escapeshellarg($network) . ' 2>&1';
$output = []; $status = 1; exec($cmd, $output, $status);
if ($status !== 0) { http_response_code(500); echo json_encode(['ok'=>false]); exit; }
echo json_encode(['ok'=>true,'network'=>strtoupper($network)]);
