#!/usr/bin/env python3
# Version: 1.0.0
# SPDX-License-Identifier: MIT

"""Surgically add FCC/worldwide names to Gateway Activity (lh.php)."""

from __future__ import annotations

import argparse
from pathlib import Path

LEGACY_MARKER = "// DVSwitch-Mods: FCC first-name activity columns v1"
OLDER_MARKER = "// DVSwitch-Mods: FCC first-name activity columns v2"
PREVIOUS_MARKER = "// DVSwitch-Mods: FCC first-name activity columns v3"
PREVIOUS_NAME_MARKER = "// DVSwitch-Mods: FCC first-name activity columns v4"
PREVIOUS_NXDN_MARKER = "// DVSwitch-Mods: FCC first-name activity columns v5"
MARKER = "// DVSwitch-Mods: FCC first-name activity columns v6"
PREVIOUS_LEGEND_MARKERS = (
    "<!-- DVSwitch-Mods: manual callsign names legend v1 -->",
    "<!-- DVSwitch-Mods: manual callsign names legend v2 -->",
    "<!-- DVSwitch-Mods: manual callsign names legend v3 -->",
)
LEGEND_MARKER = "<!-- DVSwitch-Mods: manual callsign names legend v4 -->"
STOCK_LOCALTX_LEGEND = (
    '<div style="margin:3px 0 0 14px;font-size:10px;line-height:1.3;text-align:left;white-space:normal;overflow-wrap:anywhere;">\n'
    '  <b>Legend:</b><br>\n'
    '  <b>---</b> = No name found in the local DMR ID or FCC data; country shown when available. Click --- to add an entry.\n'
    '</div>\n'
)
STOCK_LOCALTX_END = "</div>\n<br>"
TOOLTIP_STYLE = '''<style>/* DVSwitch-Mods callsign file tooltip */
.dvsModsCallsignFileTip{position:relative;display:inline-block;border-bottom:1px dotted currentColor;cursor:help;text-decoration:none;}
.dvsModsCallsignFileTip:focus{outline:1px dotted currentColor;outline-offset:2px;}
.dvsModsCallsignFileTip:hover:after,.dvsModsCallsignFileTip:focus:after{content:attr(data-tip);position:absolute;left:0;bottom:130%;z-index:10000;width:max-content;max-width:320px;padding:6px 8px;border:1px solid #aaa;border-radius:4px;background:#111;color:#fff;font:12px sans-serif;line-height:1.35;white-space:normal;box-shadow:0 2px 8px #0008;}
</style>'''
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
                $dvsModsCustomDescription = false;
                $dvsModsManualName = false;
                if ($dvsModsFirstName === '---') {
                    $dvsModsCustomDescription = dvsModsCustomCallsignDescription($listElem[2]);
                    if ($dvsModsCustomDescription !== false) { $dvsModsFirstName = $dvsModsCustomDescription; }
                    else {
                        $dvsModsManualName = dvsModsManualCallsignName($listElem[2]);
                        if ($dvsModsManualName !== false) { $dvsModsFirstName = $dvsModsManualName.'*'; }
                    }
                }
                $dvsModsCountry = ($dvsModsFirstName === '---') ? dvsModsFccCountry($listElem[2]) : '';
                $dvsModsNameHtml = htmlspecialchars($dvsModsFirstName, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8");
                if ($dvsModsFirstName === '---') {
                    $dvsModsEntryCallsign = htmlspecialchars(dvsModsNormalizeLookupCallsign($listElem[2]), ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8");
                    $dvsModsEntryIdentifier = htmlspecialchars(strtoupper(trim((string)$listElem[2])), ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8");
                    $dvsModsNameHtml = '<button type="button" title="Click to add a name or custom description for this missing entry" data-callsign="'.$dvsModsEntryCallsign.'" data-identifier="'.$dvsModsEntryIdentifier.'" style="padding:0;border:0;border-bottom:1px dotted currentColor;background:none;color:inherit;text-decoration:none;cursor:pointer;font:inherit" onclick="var c=this.getAttribute(&#39;data-callsign&#39;);var i=this.getAttribute(&#39;data-identifier&#39;);var t=window.prompt(&#39;Add &#39;+i+&#39; as:\\n1 = operator name (callsign-lookup.tsv)\\n2 = custom description (callsign-descriptions.tsv)\\nCancel = do not add&#39;,&#39;1&#39;);if(t===null)return false;t=t.trim();if(t!==&#39;1&#39;&amp;&amp;t!==&#39;2&#39;){window.alert(&#39;Choose 1 or 2.&#39;);return false;}var k=t===&#39;1&#39;?c:i;var label=t===&#39;1&#39;?&#39;operator name&#39;:&#39;custom description&#39;;var n=window.prompt(&#39;Enter the &#39;+label+&#39; for &#39;+k+&#39;:&#39;);if(n===null||!n.trim())return false;var b=this;b.disabled=true;fetch(&#39;callsign-lookup.php&#39;,{method:&#39;POST&#39;,credentials:&#39;same-origin&#39;,headers:{&#39;Content-Type&#39;:&#39;application/x-www-form-urlencoded;charset=UTF-8&#39;},body:&#39;callsign=&#39;+encodeURIComponent(k)+&#39;&amp;name=&#39;+encodeURIComponent(n)+&#39;&amp;type=&#39;+encodeURIComponent(t)}).then(function(r){return r.json().then(function(d){if(!r.ok||!d.ok)throw new Error(d.message||&#39;Could not save entry.&#39;);window.location.reload();});}).catch(function(e){window.alert(e.message);b.disabled=false;});return false;">---</button>';
                }
                if ($dvsModsCountry !== '') { $dvsModsNameHtml .= '<br>'.htmlspecialchars($dvsModsCountry, ENT_QUOTES | ENT_SUBSTITUTE, "UTF-8"); }'''
PREVIOUS_NAME_BLOCK = '''$dvsModsFirstName = dvsModsFccFirstName($listElem[2]);
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
    if text.count(LEGEND_MARKER) > 1 or any(text.count(marker) > 1 for marker in PREVIOUS_LEGEND_MARKERS):
        raise PatchError("duplicated or mixed manual callsign legend markers")
    previous_marker = next((marker for marker in PREVIOUS_LEGEND_MARKERS if marker in text), None)
    if LEGEND_MARKER in text and previous_marker is not None:
        raise PatchError("duplicated or mixed manual callsign legend markers")
    pattern = re.compile(r'(<div\b[^>]*>\s*<b>Legend:</b>.*?</div>)', re.I | re.S)
    found = list(pattern.finditer(text))
    if not found:
        # A stock DVSwitch localtx.php has no legend. The Target component is
        # intentionally installed later, so seed the shared legend at the
        # verified end-of-Local-Activity anchor instead of rejecting fresh installs.
        anchor_count = text.count(STOCK_LOCALTX_END)
        if anchor_count != 1:
            raise PatchError(
                "Local Activity legend is missing and the stock closing anchor "
                f"is unsupported or ambiguous: {anchor_count} matches"
            )
        seeded = text.replace(
            STOCK_LOCALTX_END,
            STOCK_LOCALTX_END + "\n" + STOCK_LOCALTX_LEGEND,
            1,
        )
        return patch_legend_text(seeded)
    if len(found) != 1:
        raise PatchError(f"unsupported or ambiguous Local Activity legend: {len(found)} matches")
    block = found[0].group(1)
    # Migrate wording from the existing Target/FCC combined legend. The Target
    # installer preserves this block because the FCC mod owns its extra row.
    block = re.sub(
        r"No name found in the local DMR ID or FCC data; country shown when available\.(?! Click --- to add an entry\.)",
        "No name found in the local DMR ID or FCC data; country shown when available. Click --- to add an entry.",
        block,
    ).replace(
        "No usable worldwide DMR ID or FCC name data available, Maybe an International Callsign.",
        "No name found in the local DMR ID or FCC data; country shown when available. Click --- to add an entry.",
    ).replace(
        "no usable worldwide DMR or FCC name data available",
        "No name found in the local DMR ID or FCC data; country shown when available. Click --- to add an entry.",
    )
    old_manual_description = ('Name entered and saved by you in the local callsign file. '
                              '<span title="Manually entered callsign names are stored in /etc/dvswitch-mods/callsign-lookup.tsv.">Database</span>')
    new_manual_description = ('Operator name entered manually and saved in the local callsign names file '
                              '(<span class="dvsModsCallsignFileTip" tabindex="0" title="Path: /etc/dvswitch-mods/callsign-lookup.tsv" '
                              'data-tip="Manual operator names file: /etc/dvswitch-mods/callsign-lookup.tsv">file location</span>)')
    block = block.replace(old_manual_description, new_manual_description)
    block = block.replace(
        'Name entered manually and saved in the local callsign names file',
        'Operator name entered manually and saved in the local callsign names file',
    ).replace(
        '<span title="Manual callsign names are stored in /etc/dvswitch-mods/callsign-lookup.tsv.">file location</span>',
        '<span class="dvsModsCallsignFileTip" tabindex="0" title="Path: /etc/dvswitch-mods/callsign-lookup.tsv" data-tip="Manual operator names file: /etc/dvswitch-mods/callsign-lookup.tsv">file location</span>',
    )
    if LEGEND_MARKER in block:
        if block.count(LEGEND_MARKER) != 1 or '/etc/dvswitch-mods/callsign-lookup.tsv' not in block:
            raise PatchError("incomplete or duplicated manual callsign legend")
        # Re-run formatting so wording/alignment improvements update installed legends.
    elif previous_marker is not None:
        if block.count(previous_marker) != 1 or '/etc/dvswitch-mods/callsign-lookup.tsv' not in block:
            raise PatchError("incomplete or duplicated previous manual callsign legend")
        block = block.replace(previous_marker, LEGEND_MARKER, 1)
    else:
        extra = ('<br>\n  <b>*</b> = Operator name entered manually and saved in the local callsign names file '
                 '(<span class="dvsModsCallsignFileTip" tabindex="0" title="Path: /etc/dvswitch-mods/callsign-lookup.tsv" '
                 'data-tip="Manual operator names file: /etc/dvswitch-mods/callsign-lookup.tsv">file location</span>)'
                 '<br>\n  '
                 + LEGEND_MARKER + '\n')
        block = block.replace('</div>', extra + '</div>', 1)

    # Keep the heading separate so it does not shift the first legend row.
    block = re.sub(r'(<b\b[^>]*>\s*Legend:\s*</b>)(?:[ \t\r\n]*<br>[ \t\r\n]*)*', r'\1<br>\n', block, count=1, flags=re.I)
    block = re.sub(
        r'(?m)^[ \t]*(?=<span style="display:inline-block;width:\d+ch;text-align:right(?:;margin-left:8ch)?;">)',
        '  ',
        block,
    )
    # HTML collapses leading spaces in this legend. Put the requested eight-
    # character indent on each fixed-width term span so the entire row moves.
    block = re.sub(
        r'<span style="display:inline-block;width:(\d+)ch;text-align:right;">',
        r'<span style="display:inline-block;width:\1ch;text-align:right;margin-left:8ch;">',
        block,
    )

    # Wrap each bold legend term in a fixed-width span. Keeping the bold term
    # itself unchanged preserves compatibility with the Target legend patcher.
    term_pattern = re.compile(r'(<b\b(?P<attrs>[^>]*)>)(?P<label>[^<]*)</b>(?P<space>\s*)=')
    terms = list(term_pattern.finditer(block))
    if not terms:
        already_aligned = re.search(r'<span style="display:inline-block;width:\d+ch;text-align:right(?:;margin-left:8ch)?;"><b\b[^>]*>[^<]*</b></span>\s*=', block)
        if not already_aligned:
            raise PatchError("Local Activity legend has no term/equal-sign rows to align")
        if "DVSwitch-Mods callsign file tooltip" not in block:
            block = block.replace('</div>', TOOLTIP_STYLE + '\n</div>', 1)
        return text[:found[0].start()] + block + text[found[0].end():]
    width = max(len(html.unescape(re.sub(r'<[^>]*>', '', match.group('label'))).strip()) for match in terms)
    def align_term(match):
        attrs = match.group('attrs')
        style_match = re.search(r'\sstyle\s*=\s*(["\'])(.*?)\1', attrs, re.I)
        if style_match:
            style = re.sub(r'(?:display\s*:\s*inline-block|width\s*:\s*\d+ch|text-align\s*:\s*right)\s*;?', '', style_match.group(2), flags=re.I)
            style = re.sub(r';{2,}', ';', style).strip().strip(';')
            if style:
                style += ';'
            if style:
                attrs = attrs[:style_match.start()] + f' style={style_match.group(1)}{style}{style_match.group(1)}' + attrs[style_match.end():]
            else:
                attrs = attrs[:style_match.start()] + attrs[style_match.end():]
        bold_term = f'<b{attrs}>{match.group("label")}</b>'
        return f'<span style="display:inline-block;width:{width}ch;text-align:right;margin-left:8ch;">{bold_term}</span>{match.group("space")}='
    block = term_pattern.sub(align_term, block)
    block = re.sub(
        r'(?m)^[ \t]*(?=<span style="display:inline-block;width:\d+ch;text-align:right(?:;margin-left:8ch)?;">)',
        '  ',
        block,
    )
    if "DVSwitch-Mods callsign file tooltip" not in block:
        block = block.replace('</div>', TOOLTIP_STYLE + '\n</div>', 1)
    return text[:found[0].start()] + block + text[found[0].end():]


def unpatch_legend_text(text: str) -> str:
    import re
    if LEGEND_MARKER not in text:
        return text
    pattern = re.compile(r'<br>\n\s*(?:<span style="display:inline-block;width:\d+ch;text-align:right(?:;margin-left:8ch)?;">)?<b\b[^>]*>\*</b>(?:</span>)?\s*=.*?(?:<br>\n\s*)?' + re.escape(LEGEND_MARKER) + r'\n', re.S)
    updated, count = pattern.subn('', text, count=1)
    if count != 1 or LEGEND_MARKER in updated:
        raise PatchError("manual callsign legend was changed; refusing unsafe removal")
    updated = updated.replace(TOOLTIP_STYLE + '\n', '')
    return updated


def once(text: str, old: str, new: str, description: str) -> str:
    count = text.count(old)
    if count != 1:
        raise PatchError(f"unsupported or ambiguous {description}: {count} matches")
    return text.replace(old, new, 1)


def ensure_nxdn_dispatch(text: str) -> str:
    """Add the NXDN ID resolver to an existing FCC Name-modified dashboard."""
    dispatch = '''if (strtoupper(trim((string)$listElem[1])) === "NXDN") {
                    $listElem[2] = dvsModsNxdnIdCallsign($listElem[2]);
                } else {
                    $listElem[2] = dvsModsDmrIdCallsign($listElem[2]);
                }
'''
    if text.count("dvsModsNxdnIdCallsign($listElem[2])") == 1:
        if text.count(dispatch) != 1 and not (
            text.count('if (strtoupper(trim((string)$listElem[1])) === "NXDN") {') == 1
            and text.count("$listElem[2] = dvsModsNxdnIdCallsign($listElem[2]);") == 1
        ):
            raise PatchError("existing NXDN callsign dispatch is partial or unsupported")
        return text
    if text.count("dvsModsNxdnIdCallsign($listElem[2])") > 1:
        raise PatchError("duplicate NXDN callsign dispatch")
    dmr_call = "$listElem[2] = dvsModsDmrIdCallsign($listElem[2]);"
    if text.count(dmr_call) == 1:
        line_start = text.rfind("\n", 0, text.index(dmr_call)) + 1
        indent = text[line_start:text.index(dmr_call)]
        nxdn_only = indent + '''if (strtoupper(trim((string)$listElem[1])) === "NXDN") {
                    $listElem[2] = dvsModsNxdnIdCallsign($listElem[2]);
                }
'''
        return text[:line_start] + nxdn_only + text[line_start:]
    if text.count(dmr_call) > 1:
        raise PatchError("duplicate DMR callsign dispatch")
    anchor = 'if ((is_numeric($listElem[2]) || strpos($listElem[2], "openSPOT") !== FALSE)'
    if text.count(anchor) != 1:
        raise PatchError("unsupported or ambiguous Gateway Activity callsign anchor")
    insertion = text.rfind("\n", 0, text.index(anchor)) + 1
    indent = text[insertion:text.index(anchor)]
    return text[:insertion] + indent + dispatch + text[insertion:]


def upgrade_legacy_name_region(text: str) -> str:
    """Replace an older owned Name block while preserving its existing cell output."""
    anchor = OLD_LEGACY_NAME
    if text.count(anchor) != 1:
        raise PatchError("unsupported or ambiguous legacy FCC Gateway Activity Name block")
    start = text.rfind("\n", 0, text.index(anchor)) + 1
    output_lines = []
    offset = start
    for line in text[start:].splitlines(keepends=True):
        if "echo" in line and "</td>" in line and ("$dvsModsNameHtml" in line or "htmlspecialchars($dvsModsFirstName" in line):
            output_lines.append((offset, offset + len(line), line))
        offset += len(line)
    if len(output_lines) != 1:
        raise PatchError("unsupported or ambiguous legacy FCC Gateway Activity Name output")
    output_start, output_end, output_line = output_lines[0]
    if "dvsModsFccFirstName($listElem[2])" not in text[start:output_start]:
        raise PatchError("legacy FCC Gateway Activity Name block is not recognized")
    if "$dvsModsNameHtml" not in output_line:
        output_line = '''                echo '<td align="left" style="font-weight:bold;color:#464646;white-space:normal;overflow-wrap:anywhere;word-break:normal;width:12ch;min-width:12ch;max-width:12ch;">&nbsp;<b>'.$dvsModsNameHtml.'</b></td>';\n'''
    replacement = "                " + NAME_BLOCK + "\n" + output_line
    return text[:start] + replacement + text[output_end:]


def patch_text(text: str) -> str:
    supported_markers = (MARKER, PREVIOUS_NXDN_MARKER, PREVIOUS_NAME_MARKER, PREVIOUS_MARKER, OLDER_MARKER)
    if sum(text.count(marker) for marker in supported_markers) == 1:
        required = (INCLUDE, "dvsModsFccFirstName($listElem[2])",
                    "dvsModsDmrIdCallsign($listElem[2])", "<th>Name</th>")
        if text.count(MARKER) == 0:
            old_marker = next(marker for marker in (PREVIOUS_NXDN_MARKER, PREVIOUS_NAME_MARKER, PREVIOUS_MARKER, OLDER_MARKER)
                              if text.count(marker) == 1)
            text = once(text, old_marker, MARKER, "FCC patch version marker")
        if any(text.count(token) != 1 for token in required):
            raise PatchError("incomplete FCC Gateway Activity modification")
        if text.count(NAME_BLOCK) != 1:
            if text.count(PREVIOUS_NAME_BLOCK) == 1:
                text = text.replace(PREVIOUS_NAME_BLOCK, NAME_BLOCK, 1)
            elif text.count(OLD_NAME_BLOCK) == 1:
                text = text.replace(OLD_NAME_BLOCK, NAME_BLOCK, 1)
            elif text.count(OLD_COUNTRY_BLOCK) == 1:
                text = text.replace(OLD_COUNTRY_BLOCK, NAME_BLOCK, 1)
            elif text.count(OLD_LEGACY_NAME) == 1:
                text = upgrade_legacy_name_region(text)
            else:
                raise PatchError("unsupported or ambiguous existing Gateway Activity name block")
        if text.count(NAME_CELL_STYLE_NEW) == 1:
            return ensure_nxdn_dispatch(text)
        if text.count(NAME_CELL_STYLE_PREVIOUS) == 1:
            return ensure_nxdn_dispatch(text.replace(NAME_CELL_STYLE_PREVIOUS, NAME_CELL_STYLE_NEW, 1))
        if text.count(NAME_CELL_STYLE_LEGACY_WIDTH) == 1:
            return ensure_nxdn_dispatch(text.replace(NAME_CELL_STYLE_LEGACY_WIDTH, NAME_CELL_STYLE_NEW, 1))
        if text.count(NAME_CELL_STYLE_OLD) == 1:
            text = text.replace(NAME_CELL_STYLE_OLD, NAME_CELL_STYLE_NEW, 1)
            return ensure_nxdn_dispatch(text)
        raise PatchError("unsupported or ambiguous FCC Name-cell style")
    if any(text.count(marker) > 1 for marker in (MARKER, PREVIOUS_NAME_MARKER, PREVIOUS_MARKER, OLDER_MARKER, LEGACY_MARKER)):
        raise PatchError("duplicate FCC modification marker")
    if text.count(LEGACY_MARKER) == 1:
        return patch_text(text.replace(LEGACY_MARKER, OLDER_MARKER, 1))
    if any(marker in text for marker in (MARKER, PREVIOUS_NAME_MARKER, PREVIOUS_MARKER, OLDER_MARKER, LEGACY_MARKER)):
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
    return ensure_nxdn_dispatch(text)


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
