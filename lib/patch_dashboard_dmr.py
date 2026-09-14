#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Standalone DMR status.php patcher extracted from the installer."""

from pathlib import Path
import os
import re

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
// DVSwitch-Mods: DMR Master friendly-name display v8
function dvsModsDmrNetwork($master) {
        $master = strtoupper(str_replace('_', ' ', (string)$master));
        return (strpos($master, 'TGIF') !== false) ? 'TGIF' : 'BM';
}
function dvsModsDmrTalkgroup($abinfo) {
        $values = array();
        if (isset($abinfo['last_tune'])) { $values[] = trim((string)$abinfo['last_tune']); }
        if (isset($abinfo['digital']['tg'])) { $values[] = trim((string)$abinfo['digital']['tg']); }
        foreach ($values as $value) { if (preg_match('/^(?:TG\s*)?([0-9]+)$/i', $value, $m) && $m[1] !== '0') { return $m[1]; } }
        return '';
}
function dvsModsDmrName($network, $talkgroup) {
        $file = ($network === 'TGIF') ? '/var/lib/mmdvm/TGList_TGIF.txt' : '/var/lib/mmdvm/TGList_BM.txt';
        if (!is_readable($file)) { return ''; }
        foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
                if ($line === '' || strpos($line, '#') === 0) { continue; }
                $fields = explode(';', $line, 4);
                if (count($fields) === 4 && trim($fields[0]) === (string)$talkgroup && trim($fields[1]) === '0') {
                        $name = preg_replace('/\s+/u', ' ', str_replace('_', ' ', trim($fields[2])));
                        return is_string($name) ? $name : '';
                }
        }
        return '';
}
function dvsModsDmrMasterHeading($master, $abinfo) { return 'DMR '.dvsModsDmrNetwork($master).' Master'; }
function dvsModsDmrMasterDisplay($master, $abinfo) {
        $network = dvsModsDmrNetwork($master); $talkgroup = dvsModsDmrTalkgroup($abinfo);
        if ($talkgroup === '') { return htmlspecialchars((string)$master, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }
        $name = dvsModsDmrName($network, $talkgroup); $display = ($name !== '') ? $name : 'TG '.$talkgroup;
        return htmlspecialchars($display, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

'''

old_output = '''                        echo "<tr><td  style=\\"background: #ffffed;\\" colspan=\\"2\\"><span style=\\"color:#b5651d;font-weight: bold\\">".$dmrMasterHost."</span></td></tr>\\n";}'''
new_output = '''                        echo "<tr><td  style=\\"background: #ffffed;\\" colspan=\\"2\\"><span style=\\"color:#b5651d;font-weight:bold;white-space:normal;word-break:normal;overflow-wrap:anywhere;text-align:center;\\">".dvsModsDmrMasterDisplay($dmrMasterHost, $abinfo)."</span></td></tr>\\n";}'''
old_heading = '''echo "<tr><th colspan=\\"2\\">DMR Master</th></tr>\\n";'''
new_heading = '''echo "<tr><th colspan=\\"2\\">".dvsModsDmrMasterHeading($dmrMasterHost, $abinfo)."</th></tr>\\n";'''

text = path.read_text(encoding="utf-8")
if text.count(marker) == 1:
    print("ALREADY MODIFIED: DMR friendly-name display is installed.")
    raise SystemExit(0)
if text.count(marker) or text.count(include_anchor) != 1 or text.count(old_output) != 1 or text.count(old_heading) != 1:
    raise SystemExit("ERROR: unsupported or ambiguous DMR dashboard anchors")
text = text.replace(include_anchor, include_anchor + helper, 1)
text = text.replace(old_output, new_output, 1)
text = text.replace(old_heading, new_heading, 1)
path.write_text(text, encoding="utf-8")
