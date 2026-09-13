#!/bin/bash
set -euo pipefail
LIVE=/opt/MMDVM_Bridge/MMDVM_Bridge.ini
OUT=/etc/dvswitch-mods/dmr-presets
[[ $EUID -eq 0 ]] || { echo 'ERROR: Run with sudo.' >&2; exit 1; }
[[ -f $LIVE && ! -L $LIVE ]] || { echo "ERROR: Missing regular file $LIVE" >&2; exit 1; }
address(){ sed -n '/^\[DMR Network\]/,/^\[/s/^Address=//p' "$1" | head -n1; }
network(){ case "$(address "$1")" in *tgif.network*) echo TGIF;; *brandmeister*|*master.*|*repeater.net*) echo BM;; *) echo UNKNOWN;; esac; }
live_net=$(network "$LIVE")
[[ $live_net != UNKNOWN ]] || { echo 'ERROR: Active DMR network could not be identified from MMDVM_Bridge.ini.' >&2; exit 1; }
install -d -o root -g root -m 0700 "$OUT"
install -o root -g root -m 0600 "$LIVE" "$OUT/MMDVM_Bridge.$live_net.ini"
echo "Created independent $live_net preset from $LIVE."
echo "Run dvswitch-mode-buttons.sh --install to create the alternate preset with its missing password."
