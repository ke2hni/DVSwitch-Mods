#!/bin/bash
set -euo pipefail
LIVE=/opt/MMDVM_Bridge/MMDVM_Bridge.ini
OUT=/etc/dvswitch-mods/dmr-presets
[[ $EUID -eq 0 ]] || { echo 'ERROR: Run with sudo.' >&2; exit 1; }
[[ -r $LIVE ]] || { echo "ERROR: Missing $LIVE" >&2; exit 1; }
address(){ sed -n '/^\[DMR Network\]/,/^\[/s/^Address=//p' "$1" | head -n1; }
network(){ case "$(address "$1")" in *tgif.network*) echo TGIF;; *brandmeister*|*master.*|*repeater.net*) echo BM;; *) echo UNKNOWN;; esac; }
live_net=$(network "$LIVE"); [[ $live_net != UNKNOWN ]] || { echo 'ERROR: Active DMR network could not be identified.' >&2; exit 1; }
find_candidate(){ for f in /opt/MMDVM_Bridge/*.ini /opt/MMDVM_Bridge/*/*.ini; do [[ -r $f && $f != "$LIVE" ]] || continue; [[ $(network "$f") == "$1" ]] && { echo "$f"; return; }; done; }
bm_file=$( [[ $live_net == BM ]] && echo "$LIVE" || find_candidate BM )
tgif_file=$( [[ $live_net == TGIF ]] && echo "$LIVE" || find_candidate TGIF )
[[ -n ${bm_file:-} && -n ${tgif_file:-} ]] || { echo "ERROR: Could not find both BM and TGIF DVSwitch INI files in /opt/MMDVM_Bridge." >&2; echo "Active network: $live_net; BM: ${bm_file:-missing}; TGIF: ${tgif_file:-missing}" >&2; exit 1; }
install -d -o root -g root -m 0700 "$OUT"
install -o root -g root -m 0600 "$bm_file" "$OUT/MMDVM_Bridge.BM.ini"
install -o root -g root -m 0600 "$tgif_file" "$OUT/MMDVM_Bridge.TGIF.ini"
echo "Created independent BM/TGIF presets in $OUT"
