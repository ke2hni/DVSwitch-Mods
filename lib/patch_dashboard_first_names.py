#!/usr/bin/env python3
# Version: 1.0.0
# SPDX-License-Identifier: MIT

"""Surgically add FCC/worldwide names to Gateway Activity (lh.php)."""

from __future__ import annotations

import argparse
from pathlib import Path

LEGACY_MARKER = "// DVSwitch-Mods: FCC first-name activity columns v1"
PREVIOUS_MARKER = "// DVSwitch-Mods: FCC first-name activity columns v2"
MARKER = "// DVSwitch-Mods: FCC first-name activity columns v3"
PREVIOUS_LEGEND_MARKER = "<!-- DVSwitch-Mods: manual callsign names legend v1 -->"
LEGEND_MARKER = "<!-- DVSwitch-Mods: manual callsign names legend v2 -->"
INCLUDE = "include_once dirname(dirname(__FILE__)).'/include/dvswitch_mods_fcc_first_names.php';"
NAME_CELL_STYLE_OLD = 'style="font-weight:bold;color:#464646;"'
NAME_CELL_STYLE_PREVIOUS = 'style="font-weight:bold;color:#464646;white-space:normal;overflow-wrap:anywhere;word-break:normal;max-width:10ch;"'
NAME_CELL_STYLE_LEGACY_WIDTH = 'style="font-weight:bold;color:#464646;white-space:normal;overflow-wrap:anywhere;word-break:normal;width:10ch;min-width:10ch;max-width:10ch;"'
NAME_CELL_STYLE_NEW = 'style="font-weight:bold;color:#464646;white-space:normal;overflow-wrap:anywhere;word-break:normal;width:12ch;min-width:12ch;max-width:12ch;"'


class PatchError(RuntimeError):
    pass


OLD_NAME_BLOCK = "$dvsModsCustomDescription = dvsModsCustomCallsignDescription($listElem[2]);\n                $dvsModsFirstName = ($dvsModsCustomDescription !== false) ? $dvsModsCustomDescription : dvsModsFccFirstName($listElem[2]);\n                $dvsModsCountry = ($dvsModsFirstName === '---') ? dvsModsFccCountry($listElem[2]) : '';\n                $dvsModsNameHtml = htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, \"UTF-8\");\n                if ($dvsModsCountry !== '') { $dvsModsNameHtml .= '<br>'.htmlspecialchars($dvsModsCountry, ENT_QUOTES | ENT_SUBSTITUTE, \"UTF-8\"); }"
OLD_COUNTRY_BLOCK = "$dvsModsFirstName = dvsModsFccFirstName($listElem[2]);\n                $dvsModsCountry = ($dvsModsFirstName === '---') ? dvsModsFccCountry($listElem[2]) : '';\n                $dvsModsNameHtml = htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, \"UTF-8\");\n                if ($dvsModsCountry !== '') { $dvsModsNameHtml .= '<br>'.htmlspecialchars($dvsModsCountry, ENT_QUOTES | ENT_SUBSTITUTE, \"UTF-8\"); }"
OLD_LEGACY_NAME = "$dvsModsFirstName = dvsModsFccFirstName($listElem[2]);"
NAME_BLOCK = '''$dvsModsFirstName = dvsModsFccFirstName($listElem[2]);
                $dvsModsManualName = false;
                if ($dvsModsFirstName === '---') {
                    $dvsModsManualName = dvsModsManualCallsignName($listElem[2]);
                    if ($dvsModsManualName !== false) { $dvsModsFirstName = $dvsModsManualName.'*'; }
                    else {
                        $dvsModsCustomDescription = dvsModsCustomCallsignDescription($listElem[2]);
                        if ($dvsModsCustomDescription !== false) { $dvsModsFirstName = $dvsModsCustomDescription; }
                    }
                }
                $dvsModsCountry = ($dvsModsFirstName === '---') ? dvsModsFccCountry($listElem[2]) : '';
                $dvsModsNameHtml = htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8");
                if ($dvsModsFirstName === '---') {
                    $dvsModsEntryCallsign = htmlspecialchars(dvsModsNormalizeLookupCallsign($listElem[2]), ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8");
                    $dvsModsNameHtml = '<button type="button" data-callsign="'.$dvsModsEntryCallsign.'" style="padding:0;border:0;background:none;color:inherit;text-decoration:underline;cursor:pointer;font:inherit" onclick="var c=this.getAttribute(&#39;data-callsign&#39;);var n=window.prompt(&#39;Enter the name for &#39;+c+&#39;:&#39;);if(n===null||!n.trim())return false;var b=this;b.disabled=true;fetch(&#39;callsign-lookup.php&#39;,{method:&#39;POST&#39;,credentials:&#39;same-origin&#39;,headers:{&#39;Content-Type&#39;:&#39;application/x-www-form-urlencoded;charset=UTF-8&#39;},body:&#39;callsign=&#39;+encodeURIComponent(c)+&#39;&amp;name=&#39;+encodeURIComponent(n)}).then(function(r){return r.json().then(function(d){if(!r.ok||!d.ok)throw new Error(d.message||&#39;Could not save name.&#39;);window.location.reload();});}).catch(function(e){window.alert(e.message);b.disabled=false;});return false;">---</button>';
                }
                if ($dvsModsCountry !== '') { $dvsModsNameHtml .= '<br>'.htmlspecialchars($dvsModsCountry, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8"); }'''


def patch_legend_text(text: str) -> str:
    import re
    import html
    if text.count(LEGEND_MARKER) > 1 or text.count(PREVIOUS_LEGEND_MARKER) > 1 or (LEGEND_MARKER in text and PREVIOUS_LEGEND_MARKER in text):
        raise PatchError("duplicated or mixed manual callsign legend markers")
    pattern = re.compile(r'(<div\b[^>]*>\s*<b>Legend:</b>.*?</div>)', re.I | re.S)
    found = list(pattern.finditer(text))
    if len(found) != 1:
        raise PatchError(f"unsupported or ambiguous Local Activity legend: {len(found)} matches")
    block = found[0].group(1)
    if LEGEND_MARKER in block:
        if block.count(LEGEND_MARKER) != 1 or '/etc/dvswitch-mods/callsign-lookup.tsv' not in block:
            raise PatchError("incomplete or duplicated manual callsign legend")
    elif PREVIOUS_LEGEND_MARKER in block:
        if block.count(PREVIOUS_LEGEND_MARKER) != 1 or '/etc/dvswitch-mods/callsign-lookup.tsv' not in block:
            raise PatchError("incomplete or duplicated previous manual callsign legend")
        block = block.replace(PREVIOUS_LEGEND_MARKER, LEGEND_MARKER, 1)
    else:
        extra = ('<br>\n  <b>*</b> = Name entered and saved by you in the local callsign file. '
                 '<span title="Manually entered callsign names are stored in /etc/dvswitch-mods/callsign-lookup.tsv.">Database</span>\n  '
                 + LEGEND_MARKER + '\n')
        block = block.replace('</div>', extra + '</div>', 1)

    # Give each bold legend term the same width, so every equals sign and
    # description begins in the same column. Strip our prior inline style
    # before reapplying it to keep upgrades idempotent.
    term_pattern = re.compile(r'(<b\b(?P<attrs>[^>]*)>)(?P<label>[^<]*)</b>(?P<space>\s*)=')
    terms = list(term_pattern.finditer(block))
    if not terms:
        raise PatchError("Local Activity legend has no term/equal-sign rows to align")
    width = max(len(html.unescape(re.sub(r'<[^>]*>', '', match.group('label'))).strip()) for match in terms)
    def align_term(match):
        attrs = match.group('attrs')
        style_match = re.search(r'\sstyle\s*=\s*(["\'])(.*?)\1', attrs, re.I)
        if style_match:
            style = re.sub(r'(?:display\s*:\s*inline-block|width\s*:\s*\d+ch|text-align\s*:\s*right)\s*;?', '', style_match.group(2), flags=re.I)
            style = re.sub(r';{2,}', ';', style).strip().strip(';')
            if style:
                style += ';'
            style += f'display:inline-block;width:{width}ch;text-align:right;'
            attrs = attrs[:style_match.start()] + f' style={style_match.group(1)}{style}{style_match.group(1)}' + attrs[style_match.end():]
        else:
            attrs += f' style="display:inline-block;width:{width}ch;text-align:right;"'
        return f'<b{attrs}>{match.group("label")}</b>{match.group("space")}='
    block = term_pattern.sub(align_term, block)
    return text[:found[0].start()] + block + text[found[0].end():]


def unpatch_legend_text(text: str) -> str:
    import re
    if LEGEND_MARKER not in text:
        return text
    pattern = re.compile(r'<br>\n  <b>\*</b> = Name entered and saved by you in the local callsign file\. <span title="Manually entered callsign names are stored in /etc/dvswitch-mods/callsign-lookup\.tsv\."\s*>Database</span>\n  ' + re.escape(LEGEND_MARKER) + r'\n')
    updated, count = pattern.subn('', text, count=1)
    if count != 1 or LEGEND_MARKER in updated:
        raise PatchError("manual callsign legend was changed; refusing unsafe removal")
    return updated


def once(text: str, old: str, new: str, description: str) -> str:
    count = text.count(old)
    if count != 1:
        raise PatchError(f"unsupported or ambiguous {description}: {count} matches")
    return text.replace(old, new, 1)


def patch_text(text: str) -> str:
    if text.count(MARKER) == 1 or text.count(PREVIOUS_MARKER) == 1:
        required = (INCLUDE, "dvsModsFccFirstName($listElem[2])",
                    "dvsModsDmrIdCallsign($listElem[2])", "<th>Name</th>")
        if text.count(MARKER) == 0:
            text = once(text, PREVIOUS_MARKER, MARKER, "FCC patch version marker")
        if any(text.count(token) != 1 for token in required):
            raise PatchError("incomplete FCC Gateway Activity modification")
        if text.count(NAME_BLOCK) != 1:
            if text.count(OLD_NAME_BLOCK) == 1:
                text = text.replace(OLD_NAME_BLOCK, NAME_BLOCK, 1)
            elif text.count(OLD_COUNTRY_BLOCK) == 1:
                text = text.replace(OLD_COUNTRY_BLOCK, NAME_BLOCK, 1)
            elif text.count(OLD_LEGACY_NAME) == 1:
                text = text.replace(OLD_LEGACY_NAME, NAME_BLOCK, 1)
                old_output = "htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, \"UTF-8\").'</b></td>';"
                new_output = "$dvsModsNameHtml.'</b></td>';"
                if text.count(old_output) != 1:
                    raise PatchError("unsupported legacy FCC Gateway Activity Name output")
                text = text.replace(old_output, new_output, 1)
            else:
                raise PatchError("unsupported or ambiguous existing Gateway Activity name block")
        if text.count(NAME_CELL_STYLE_NEW) == 1:
            return text
        if text.count(NAME_CELL_STYLE_PREVIOUS) == 1:
            return text.replace(NAME_CELL_STYLE_PREVIOUS, NAME_CELL_STYLE_NEW, 1)
        if text.count(NAME_CELL_STYLE_LEGACY_WIDTH) == 1:
            return text.replace(NAME_CELL_STYLE_LEGACY_WIDTH, NAME_CELL_STYLE_NEW, 1)
        if text.count(NAME_CELL_STYLE_OLD) == 1:
            return text.replace(NAME_CELL_STYLE_OLD, NAME_CELL_STYLE_NEW, 1)
        raise PatchError("unsupported or ambiguous FCC Name-cell style")
    if text.count(MARKER) > 1 or text.count(PREVIOUS_MARKER) > 1 or text.count(LEGACY_MARKER) > 1:
        raise PatchError("duplicate FCC modification marker")
    if text.count(LEGACY_MARKER) == 1:
        return patch_text(text.replace(LEGACY_MARKER, MARKER, 1))
    if MARKER in text or LEGACY_MARKER in text:
        raise PatchError("partial FCC modification marker")
    if not text.startswith("<?php\n"):
        raise PatchError("unsupported lh.php PHP anchor")

    text = text.replace("<?php\n", "<?php\n" + MARKER + "\n", 1)
    text = once(text,
        "include_once dirname(dirname(__FILE__)).'/include/functions.php';    \n",
        "include_once dirname(dirname(__FILE__)).'/include/functions.php';    \n" + INCLUDE + "\n",
        "Gateway Activity include anchor")
    text = once(text, "      <th>Time (<?php echo date('T')?>)</th>",
                "      <th style=\"white-space:nowrap;width:115px;\">Time (<?php echo date('T')?>)</th>",
                "Gateway Activity time header")
    old_header = '''      <th>Callsign</th>
<?php
    if (DISPLAYNAME == "YES" && file_exists(DMRIDDATPATH."/DMRIds.dat") && ! empty(DMRIDDATPATH."/DMRIds.dat")) { echo "<th>Name</th>"; }
?>'''
    text = once(text, old_header, "      <th>Callsign</th>\n      <th>Name</th>", "Gateway Activity name header")
    start_token = "// Display NAME by DV8AWC"
    end_tokens = ["if (strlen($listElem[4]) == 1)",
                  "$dvsModsTarget = dvsModsTargetDisplay($listElem[1], $listElem[4], $listElem[6]);"]
    end_token = next((token for token in end_tokens if text.count(token) == 1), None)
    if text.count(start_token) != 1 or end_token is None:
        raise PatchError("unsupported or ambiguous Gateway Activity name block")
    start = text.rfind("\n", 0, text.index(start_token)) + 1
    end = text.rfind("\n", 0, text.index(end_token)) + 1
    if start >= end:
        raise PatchError("invalid Gateway Activity name-block order")
    replacement = "                " + NAME_BLOCK + '''
                echo '<td align="left" style="font-weight:bold;color:#464646;white-space:normal;overflow-wrap:anywhere;word-break:normal;width:12ch;min-width:12ch;max-width:12ch;">&nbsp;<b>'.$dvsModsNameHtml.'</b></td>';
'''
    text = text[:start] + replacement + text[end:]
    token = 'if ((is_numeric($listElem[2]) || strpos($listElem[2], "openSPOT") !== FALSE)'
    if text.count(token) != 1:
        raise PatchError(f"unsupported or ambiguous Gateway Activity callsign anchor: {text.count(token)} matches")
    insertion = text.rfind("\n", 0, text.index(token)) + 1
    indent = text[insertion:text.index(token)]
    return text[:insertion] + indent + "$listElem[2] = dvsModsDmrIdCallsign($listElem[2]);\n" + text[insertion:]


def patch_file(path: Path) -> None:
    raw = path.read_bytes()
    if b"\r" in raw.replace(b"\r\n", b""):
        raise PatchError(f"unsupported mixed line endings in {path}")
    newline = "\r\n" if b"\r\n" in raw else "\n"
    result = patch_text(raw.decode("utf-8").replace("\r\n", "\n"))
    path.write_bytes(result.replace("\n", newline).encode("utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lh", type=Path, required=True)
    parser.add_argument("--localtx", type=Path)
    args = parser.parse_args()
    if args.lh.name != "lh.php":
        raise PatchError("FCC patcher accepts only lh.php; Local Activity is intentionally untouched")
    patch_file(args.lh)
    if args.localtx is not None:
        if args.localtx.name != "localtx.php":
            raise PatchError("FCC legend patcher accepts only localtx.php")
        raw = args.localtx.read_bytes()
        if b"\r" in raw.replace(b"\r\n", b""):
            raise PatchError(f"unsupported mixed line endings in {args.localtx}")
        newline = "\r\n" if b"\r\n" in raw else "\n"
        updated = patch_legend_text(raw.decode("utf-8").replace("\r\n", "\n"))
        args.localtx.write_bytes(updated.replace("\n", newline).encode("utf-8"))


if __name__ == "__main__":
    try:
        main()
    except PatchError as exc:
        raise SystemExit(f"ERROR: {exc}")
