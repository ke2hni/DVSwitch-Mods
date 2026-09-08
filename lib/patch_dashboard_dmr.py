#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Standalone DMR status.php patcher extracted from the installer."""

from pathlib import Path
import os

path = Path(os.environ["STATUS_CANDIDATE"])
marker = os.environ["DVS_MOD_MARKER"]
v1_marker = "// DVSwitch-Mods: DMR Master friendly-name display v1"
v2_marker = "// DVSwitch-Mods: DMR Master friendly-name display v2"
v3_marker = "// DVSwitch-Mods: DMR Master friendly-name display v3"
v4_marker = "// DVSwitch-Mods: DMR Master friendly-name display v4"
v5_marker = "// DVSwitch-Mods: DMR Master friendly-name display v5"
v6_marker = "// DVSwitch-Mods: DMR Master friendly-name display v6"

include_anchor = "include_once dirname(dirname(__FILE__)).'/include/functions.php';\n"
helper = r'''
// DVSwitch-Mods: DMR Master friendly-name display v7
function dvsModsDmrNetwork($master) {
        $master = strtoupper(str_replace('_', ' ', (string)$master));
        if (strpos($master, 'TGIF') !== false) { return 'TGIF'; }
        return 'BM';
}

function dvsModsDmrStateRead() {
        $file = '/var/lib/mmdvm/dvswitch-mods-dmr-state.json';
        if (!is_readable($file)) { return array(); }
        $state = json_decode(file_get_contents($file), true);
        return is_array($state) ? $state : array();
}

function dvsModsDmrStateWrite($state) {
        $file = '/var/lib/mmdvm/dvswitch-mods-dmr-state.json';
        $json = json_encode($state, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
        if ($json === false || !is_writable($file)) { return false; }
        return file_put_contents($file, $json."\n", LOCK_EX) !== false;
}

function dvsModsDmrMasterHeading($master, $abinfo) {
        $state = dvsModsDmrStateRead();
        $mode = isset($abinfo['tlv']['ambe_mode']) ? strtoupper(trim((string)$abinfo['tlv']['ambe_mode'])) : '';
        if ($mode === 'STFU') {
                $network = 'BM';
        } else if ($mode === 'DMR') {
                $network = dvsModsDmrNetwork($master);
        } else if (isset($state['current_network']) && ($state['current_network'] === 'BM' || $state['current_network'] === 'TGIF')) {
                $network = $state['current_network'];
        } else {
                $network = dvsModsDmrNetwork($master);
        }
        return 'DMR '.$network.' Master';
}

function dvsModsDmrTalkgroup($abinfo) {
        $values = array();
        if (isset($abinfo['last_tune'])) { $values[] = trim((string)$abinfo['last_tune']); }
        if (isset($abinfo['digital']['tg'])) { $values[] = trim((string)$abinfo['digital']['tg']); }
        foreach ($values as $value) {
                if (preg_match('/^(?:TG\s*)?([0-9]+)$/i', $value, $matches) && $matches[1] !== '0') { return $matches[1]; }
        }
        return '';
}

function dvsModsDmrName($network, $talkgroup) {
        $file = ($network === 'TGIF') ? '/var/lib/mmdvm/TGList_TGIF.txt' : '/var/lib/mmdvm/TGList_BM.txt';
        if (!is_readable($file)) { return ''; }
        $lines = file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        if (!is_array($lines)) { return ''; }
        foreach ($lines as $line) {
                if ($line === '' || strpos($line, '#') === 0) { continue; }
                $fields = explode(';', $line, 4);
                if (count($fields) === 4 && trim($fields[0]) === (string)$talkgroup && trim($fields[1]) === '0') {
                        $name = preg_replace('/\s+/u', ' ', str_replace('_', ' ', trim($fields[2])));
                        return is_string($name) ? $name : '';
                }
        }
        return '';
}

function dvsModsDmrForeignTalkgroup($talkgroup) {
        foreach (array('/var/lib/mmdvm/YSFHosts.txt', '/var/lib/mmdvm/P25Hosts.txt', '/var/lib/mmdvm/NXDNHosts.txt') as $file) {
                if (!is_readable($file)) { continue; }
                $lines = file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
                if (!is_array($lines)) { continue; }
                foreach ($lines as $line) {
                        if ($line === '' || strpos($line, '#') === 0) { continue; }
                        $fields = explode(';', $line, 2);
                        if (trim($fields[0]) === (string)$talkgroup) { return true; }
                }
        }
        foreach (array('/var/lib/mmdvm/P25Hosts.json', '/var/lib/mmdvm/NXDNHosts.json') as $file) {
                if (!is_readable($file)) { continue; }
                $json = json_decode(file_get_contents($file), true);
                if (!isset($json['reflectors']) || !is_array($json['reflectors'])) { continue; }
                foreach ($json['reflectors'] as $row) {
                        if (is_array($row) && isset($row['designator']) && (string)$row['designator'] === (string)$talkgroup) { return true; }
                }
        }
        return false;
}

function dvsModsDmrMasterDisplay($master, $abinfo) {
        $state = dvsModsDmrStateRead();
        $originalState = $state;
        $mode = isset($abinfo['tlv']['ambe_mode']) ? strtoupper(trim((string)$abinfo['tlv']['ambe_mode'])) : '';
        $network = ($mode === 'STFU') ? 'BM' : dvsModsDmrNetwork($master);
        $liveTalkgroup = dvsModsDmrTalkgroup($abinfo);
        $previousMode = isset($state['observed_mode']) ? strtoupper(trim((string)$state['observed_mode'])) : '';
        $previousNetwork = isset($state['observed_network']) ? strtoupper(trim((string)$state['observed_network'])) : '';
        $previousTalkgroup = isset($state['observed_tg']) ? trim((string)$state['observed_tg']) : '';
        $isDmr = ($mode === 'DMR' || $mode === 'STFU');
        if (!$isDmr) {
                unset($state['blocked_tg']);
        } else {
                $blocked = isset($state['blocked_tg']) ? trim((string)$state['blocked_tg']) : '';
                if ($mode === 'DMR' && $network === 'TGIF' && $liveTalkgroup === '9' && isset($state[$network]['tg']) && dvsModsDmrName($network, (string)$state[$network]['tg']) === '' && dvsModsDmrForeignTalkgroup((string)$state[$network]['tg'])) {
                        unset($state[$network]);
                }
                $transition = ($previousMode !== '' && $previousMode !== $mode) || ($previousNetwork !== '' && $previousNetwork !== $network);
                if ($transition && $liveTalkgroup !== '' && $liveTalkgroup === $previousTalkgroup) {
                        $blocked = $liveTalkgroup;
                }
                if ($previousMode === '' && $liveTalkgroup !== '' && isset($state[$network]['tg']) && (string)$state[$network]['tg'] === $liveTalkgroup && dvsModsDmrName($network, $liveTalkgroup) === '' && dvsModsDmrForeignTalkgroup($liveTalkgroup)) {
                        $blocked = $liveTalkgroup;
                        unset($state[$network]);
                }
                if ($blocked !== '' && $liveTalkgroup !== '' && $liveTalkgroup !== $blocked) { $blocked = ''; }
                if ($blocked !== '' && isset($state[$network]['tg']) && (string)$state[$network]['tg'] === $blocked && dvsModsDmrName($network, $blocked) === '' && dvsModsDmrForeignTalkgroup($blocked)) {
                        unset($state[$network]);
                }
                if ($blocked !== '') { $state['blocked_tg'] = $blocked; }
                else { unset($state['blocked_tg']); }
                if ($liveTalkgroup !== '' && $liveTalkgroup !== $blocked && !($mode === 'DMR' && $network === 'TGIF' && $liveTalkgroup === '9')) {
                        $state[$network] = array('tg' => $liveTalkgroup);
                        $state['current_network'] = $network;
                }
        }
        $state['observed_mode'] = ($mode !== '') ? $mode : 'ASL';
        if ($isDmr) { $state['observed_network'] = $network; }
        else { unset($state['observed_network']); }
        if ($liveTalkgroup !== '') { $state['observed_tg'] = $liveTalkgroup; }
        else { unset($state['observed_tg']); }
        if ($state !== $originalState) { dvsModsDmrStateWrite($state); }
        if (!$isDmr && isset($state['current_network']) && ($state['current_network'] === 'BM' || $state['current_network'] === 'TGIF')) {
                $network = $state['current_network'];
        }
        $talkgroup = '';
        if (isset($state[$network]) && is_array($state[$network]) && isset($state[$network]['tg'])) {
                $candidate = trim((string)$state[$network]['tg']);
                if (preg_match('/^[0-9]+$/', $candidate) && $candidate !== '0') { $talkgroup = $candidate; }
        }
        $blocked = isset($state['blocked_tg']) ? trim((string)$state['blocked_tg']) : '';
        if ($talkgroup === '' && $isDmr && $liveTalkgroup !== $blocked && !($mode === 'DMR' && $network === 'TGIF' && $liveTalkgroup === '9')) { $talkgroup = $liveTalkgroup; }
        if ($talkgroup === '') { return htmlspecialchars((string)$master, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }
        $name = dvsModsDmrName($network, $talkgroup);
        $display = ($name !== '') ? $name : 'TG '.$talkgroup;
        return htmlspecialchars($display, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

'''

old_output = '''                        echo "<tr><td  style=\\"background: #ffffed;\\" colspan=\\"2\\"><span style=\\"color:#b5651d;font-weight: bold\\">".$dmrMasterHost."</span></td></tr>\\n";}'''
v2_output = '''                        echo "<tr><td  style=\\"background: #ffffed;\\" colspan=\\"2\\"><span style=\\"color:#b5651d;font-weight: bold\\">".dvsModsDmrMasterDisplay($dmrMasterHost, $abinfo)."</span></td></tr>\\n";}'''
new_output = '''                        echo "<tr><td  style=\\"background: #ffffed;\\" colspan=\\"2\\"><span style=\\"color:#b5651d;font-weight:bold;white-space:normal;word-break:normal;overflow-wrap:anywhere;text-align:center;\\">".dvsModsDmrMasterDisplay($dmrMasterHost, $abinfo)."</span></td></tr>\\n";}'''
old_heading = '''echo "<tr><th colspan=\\"2\\">DMR Master</th></tr>\\n";'''
new_heading = '''echo "<tr><th colspan=\\"2\\">".dvsModsDmrMasterHeading($dmrMasterHost, $abinfo)."</th></tr>\\n";'''

old_log_lookup = '''\t\tif (file_exists("/var/log/mmdvm/MMDVM_Bridge-".gmdate("Y-m-d").".log")) { $dmrstat = exec('grep -a \\'DMR, Logged\\|DMR, Closing DMR\\|DMR, Opening DMR\\|DMR, Connection\\' /var/log/mmdvm/MMDVM_Bridge-'.gmdate("Y-m-d").'.log | tail -1 | awk \\'{print $5 " " $10}\\'');
\t\t} else {$dmrstat = exec('grep -a \\'DMR, Logged\\|DMR, Closing DMR\\|DMR, Opening DMR\\|DMR, Connection\\' /var/log/mmdvm/MMDVM_Bridge-'.gmdate("Y-m-d", time() - 86340).'.log | tail -1 | awk \\'{print $5 " " $10}\\''); }'''
new_log_lookup = '''\t\t$dmrstat = '';
\t\tif (file_exists("/var/log/mmdvm/MMDVM_Bridge-".gmdate("Y-m-d").".log")) { $dmrstat = exec('grep -a \\'DMR, Logged\\|DMR, Closing DMR\\|DMR, Opening DMR\\|DMR, Connection\\' /var/log/mmdvm/MMDVM_Bridge-'.gmdate("Y-m-d").'.log | tail -1 | awk \\'{print $5 " " $10}\\''); }
\t\tif ($dmrstat === '' && file_exists("/var/log/mmdvm/MMDVM_Bridge-".gmdate("Y-m-d", time() - 86340).".log")) { $dmrstat = exec('grep -a \\'DMR, Logged\\|DMR, Closing DMR\\|DMR, Opening DMR\\|DMR, Connection\\' /var/log/mmdvm/MMDVM_Bridge-'.gmdate("Y-m-d", time() - 86340).'.log | tail -1 | awk \\'{print $5 " " $10}\\''); }'''
old_status_condition = "\t\telse if (strpos($dmrstat, 'Opening') !== false || strpos($dmrstatus, 'Closing') !== false || strpos($dmrstatus, 'Connection') !== false) { "
new_status_condition = "\t\telse if (strpos($dmrstat, 'Opening') !== false || strpos($dmrstat, 'Closing') !== false || strpos($dmrstat, 'Connection') !== false) { "

v3_master = r'''function dvsModsDmrMasterDisplay($master, $abinfo) {
        $state = dvsModsDmrStateRead();
        $mode = isset($abinfo['tlv']['ambe_mode']) ? strtoupper(trim((string)$abinfo['tlv']['ambe_mode'])) : '';
        $network = ($mode === 'STFU') ? 'BM' : dvsModsDmrNetwork($master);
        if ($mode === 'DMR' || $mode === 'STFU') {
                $talkgroup = dvsModsDmrTalkgroup($abinfo);
                if ($talkgroup !== '' && !($mode === 'DMR' && $network === 'TGIF' && $talkgroup === '9')) {
                        $state[$network] = array('tg' => $talkgroup);
                        $state['current_network'] = $network;
                        dvsModsDmrStateWrite($state);
                }
        } else if (isset($state['current_network']) && ($state['current_network'] === 'BM' || $state['current_network'] === 'TGIF')) {
                $network = $state['current_network'];
        }
        $talkgroup = '';
        if (isset($state[$network]) && is_array($state[$network]) && isset($state[$network]['tg'])) {
                $candidate = trim((string)$state[$network]['tg']);
                if (preg_match('/^[0-9]+$/', $candidate) && $candidate !== '0') { $talkgroup = $candidate; }
        }
        if ($talkgroup === '' && ($mode === 'DMR' || $mode === 'STFU')) { $talkgroup = dvsModsDmrTalkgroup($abinfo); }
        if ($talkgroup === '') { return htmlspecialchars((string)$master, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }
        $name = dvsModsDmrName($network, $talkgroup);
        $display = ($name !== '') ? $name : 'TG '.$talkgroup;
        return htmlspecialchars($display, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
'''
v6_cleanup = r'''                if ($mode === 'DMR' && $network === 'TGIF' && $liveTalkgroup === '9' && isset($state[$network]['tg']) && dvsModsDmrName($network, (string)$state[$network]['tg']) === '' && dvsModsDmrForeignTalkgroup((string)$state[$network]['tg'])) {
                        unset($state[$network]);
                }
'''
v5_fallback = "        if ($talkgroup === '' && $isDmr && $liveTalkgroup !== $blocked) { $talkgroup = $liveTalkgroup; }"
v6_fallback = "        if ($talkgroup === '' && $isDmr && $liveTalkgroup !== $blocked && !($mode === 'DMR' && $network === 'TGIF' && $liveTalkgroup === '9')) { $talkgroup = $liveTalkgroup; }"
heading_helper = r'''function dvsModsDmrMasterHeading($master, $abinfo) {
        $state = dvsModsDmrStateRead();
        $mode = isset($abinfo['tlv']['ambe_mode']) ? strtoupper(trim((string)$abinfo['tlv']['ambe_mode'])) : '';
        if ($mode === 'STFU') {
                $network = 'BM';
        } else if ($mode === 'DMR') {
                $network = dvsModsDmrNetwork($master);
        } else if (isset($state['current_network']) && ($state['current_network'] === 'BM' || $state['current_network'] === 'TGIF')) {
                $network = $state['current_network'];
        } else {
                $network = dvsModsDmrNetwork($master);
        }
        return 'DMR '.$network.' Master';
}

'''
v6_helper = helper.replace(marker, v6_marker, 1).replace(heading_helper, '', 1)
v5_helper = v6_helper.replace(v6_marker, v5_marker, 1).replace(v6_cleanup, '', 1).replace(v6_fallback, v5_fallback, 1)
v4_helper = v5_helper.replace(v5_marker, v4_marker, 1)
v6_start = helper.index('function dvsModsDmrForeignTalkgroup(')
v6_master = helper[v6_start:].rstrip() + "\n"
v5_start = v5_helper.index('function dvsModsDmrForeignTalkgroup(')
v5_master = v5_helper[v5_start:].rstrip() + "\n"

text = path.read_text(encoding="utf-8")
markers = text.count(marker)
v1_markers = text.count(v1_marker)
v2_markers = text.count(v2_marker)
v3_markers = text.count(v3_marker)
v4_markers = text.count(v4_marker)
v5_markers = text.count(v5_marker)
v6_markers = text.count(v6_marker)
v3_helper = helper.replace(marker, v3_marker, 1).replace(v6_master, v3_master, 1)
v2_helper = v3_helper.replace(v3_marker, v2_marker, 1)

old_logic = r'''        $network = dvsModsDmrNetwork($master);
        if ($mode === 'DMR') {
                $talkgroup = dvsModsDmrTalkgroup($abinfo);
                if ($talkgroup !== '' && !($network === 'TGIF' && $talkgroup === '9')) {'''
new_logic = r'''        $network = ($mode === 'STFU') ? 'BM' : dvsModsDmrNetwork($master);
        if ($mode === 'DMR' || $mode === 'STFU') {
                $talkgroup = dvsModsDmrTalkgroup($abinfo);
                if ($talkgroup !== '' && !($mode === 'DMR' && $network === 'TGIF' && $talkgroup === '9')) {'''
old_fallback = "        if ($talkgroup === '' && $mode === 'DMR') { $talkgroup = dvsModsDmrTalkgroup($abinfo); }"
new_fallback = "        if ($talkgroup === '' && ($mode === 'DMR' || $mode === 'STFU')) { $talkgroup = dvsModsDmrTalkgroup($abinfo); }"

if markers == 0 and v1_markers == 0 and v2_markers == 0 and v3_markers == 0 and v4_markers == 0 and v5_markers == 0 and v6_markers == 0:
    counts = (text.count(include_anchor), text.count(old_output), text.count(v2_output), text.count(new_output))
    if counts != (1, 1, 0, 0):
        raise SystemExit("ERROR: unsupported or ambiguous DMR Master anchors: " + repr(counts))
    if 'function dvsModsDmrMasterDisplay(' in text:
        raise SystemExit("ERROR: unexpected existing DMR friendly-name code")
    text = text.replace(include_anchor, include_anchor + helper, 1)
    text = text.replace(old_output, new_output, 1)
elif markers == 0 and v1_markers == 1 and v2_markers == 0 and v3_markers == 0 and v4_markers == 0 and v5_markers == 0 and v6_markers == 0:
    counts = (text.count(old_logic), text.count(new_logic), text.count(old_fallback), text.count(new_fallback), text.count(v2_output), text.count(new_output))
    if counts != (1, 0, 1, 0, 1, 0):
        raise SystemExit("ERROR: incomplete or ambiguous v1 STFU upgrade anchors: " + repr(counts))
    text = text.replace(v1_marker, marker, 1)
    text = text.replace(old_logic, new_logic, 1)
    text = text.replace(old_fallback, new_fallback, 1)
    text = text.replace(v3_master, v6_master, 1)
    text = text.replace(v2_output, new_output, 1)
elif markers == 0 and v1_markers == 0 and v2_markers == 1 and v3_markers == 0 and v4_markers == 0 and v5_markers == 0 and v6_markers == 0:
    if text.count(v2_helper) != 1 or text.count(v2_output) != 1 or text.count(new_output) != 0 or text.count(old_output) != 0:
        raise SystemExit("ERROR: incomplete or ambiguous DMR v2 friendly-name modification")
    ysf_markers = text.count("// DVSwitch-Mods: YSF dashboard null repair v1")
    if ysf_markers not in (0, 1):
        raise SystemExit("ERROR: unexpected YSF marker in DMR-only dashboard state")
    text = text.replace(v2_marker, marker, 1)
    text = text.replace(v3_master, v6_master, 1)
    text = text.replace(v2_output, new_output, 1)
elif markers == 0 and v1_markers == 0 and v2_markers == 0 and v3_markers == 1 and v4_markers == 0 and v5_markers == 0 and v6_markers == 0:
    if text.count(v3_helper) != 1 or text.count(new_output) != 1 or text.count(v2_output) != 0 or text.count(old_output) != 0:
        raise SystemExit("ERROR: incomplete or ambiguous DMR v3 friendly-name modification")
    v2_text = text.replace(v3_marker, v2_marker, 1).replace(new_output, v2_output, 1)
    text = text.replace(v3_marker, marker, 1)
    text = text.replace(v3_master, v6_master, 1)
elif markers == 0 and v1_markers == 0 and v2_markers == 0 and v3_markers == 0 and v4_markers == 1 and v5_markers == 0 and v6_markers == 0:
    if text.count(v4_helper) != 1 or text.count(new_output) != 1 or text.count(v2_output) != 0 or text.count(old_output) != 0:
        raise SystemExit("ERROR: incomplete or ambiguous DMR v4 friendly-name modification")
    text = text.replace(v4_helper, helper, 1)
elif markers == 0 and v1_markers == 0 and v2_markers == 0 and v3_markers == 0 and v4_markers == 0 and v5_markers == 1 and v6_markers == 0:
    if text.count(v5_helper) != 1 or text.count(new_output) != 1 or text.count(v2_output) != 0 or text.count(old_output) != 0:
        raise SystemExit("ERROR: incomplete or ambiguous DMR v5 friendly-name modification")
    text = text.replace(v5_helper, helper, 1)
elif markers == 0 and v1_markers == 0 and v2_markers == 0 and v3_markers == 0 and v4_markers == 0 and v5_markers == 0 and v6_markers == 1:
    if text.count(v6_helper) != 1 or text.count(new_output) != 1 or text.count(v2_output) != 0 or text.count(old_output) != 0:
        raise SystemExit("ERROR: incomplete or ambiguous DMR v6 friendly-name modification")
    reversible_text = text.replace(v6_helper, v5_helper, 1).replace(new_log_lookup, old_log_lookup, 1).replace(new_status_condition, old_status_condition, 1)
    v3_text = reversible_text.replace(v5_marker, v3_marker, 1).replace(v5_master, v3_master, 1)
    v2_text = v3_text.replace(v3_marker, v2_marker, 1).replace(new_output, v2_output, 1)
    text = text.replace(v6_helper, helper, 1)
elif markers == 1 and v1_markers == 0 and v2_markers == 0 and v3_markers == 0 and v4_markers == 0 and v5_markers == 0 and v6_markers == 0:
    if text.count(helper) != 1 or text.count(new_output) != 1 or text.count(v2_output) != 0 or text.count(old_output) != 0:
        raise SystemExit("ERROR: incomplete or ambiguous DMR friendly-name modification")
    reversible_text = text.replace(helper, v5_helper, 1).replace(new_heading, old_heading, 1).replace(new_log_lookup, old_log_lookup, 1).replace(new_status_condition, old_status_condition, 1)
    v3_text = reversible_text.replace(v5_marker, v3_marker, 1).replace(v5_master, v3_master, 1)
    v2_text = v3_text.replace(v3_marker, v2_marker, 1).replace(new_output, v2_output, 1)
    ysf_markers = text.count("// DVSwitch-Mods: YSF dashboard null repair v1")
    if ysf_markers not in (0, 1):
        raise SystemExit("ERROR: unexpected YSF marker in DMR-only dashboard state")
else:
    raise SystemExit("ERROR: duplicate or mixed DMR friendly-name modification markers")

heading_counts = (text.count(old_heading), text.count(new_heading))
if heading_counts == (1, 0):
    text = text.replace(old_heading, new_heading, 1)
elif heading_counts != (0, 1):
    raise SystemExit("ERROR: incomplete or ambiguous DMR Master heading anchors: " + repr(heading_counts))

log_counts = (text.count(old_log_lookup), text.count(new_log_lookup), text.count(old_status_condition), text.count(new_status_condition))
if log_counts == (1, 0, 1, 0):
    text = text.replace(old_log_lookup, new_log_lookup, 1)
    text = text.replace(old_status_condition, new_status_condition, 1)
elif log_counts != (0, 1, 0, 1):
    raise SystemExit("ERROR: incomplete or ambiguous DMR log-status repair anchors: " + repr(log_counts))

path.write_text(text, encoding="utf-8")

