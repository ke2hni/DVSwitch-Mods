#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$REPO_ROOT/install-dvswitch-mods.sh"
fail(){ printf 'TEST FAILURE: %s\n' "$1" >&2; exit 1; }
[[ -f "$INSTALLER" ]] || fail "installer is missing"
bash -n "$INSTALLER" || fail "installer failed shell syntax validation"
grep -Fq 'SPDX-License-Identifier: MIT' "$INSTALLER" || fail "MIT SPDX identifier is missing"
grep -Fq 'Copyright (c) 2026 Jeff Milne, KE2HNI' "$INSTALLER" || fail "copyright notice is missing"
help_output="$(bash "$INSTALLER" --help)"
grep -Fq 'DVSwitch Mods installer 0.3.0-rc1' <<<"$help_output" || fail "version is missing"
grep -Fq 'Usage:' <<<"$help_output" || fail "usage text is missing"
set +e
no_argument_output="$(bash "$INSTALLER" 2>&1)"; no_argument_status=$?
unknown_output="$(bash "$INSTALLER" --not-a-real-option 2>&1)"; unknown_status=$?
set -e
[[ $no_argument_status -eq 2 ]] || fail "no-argument status is not 2"
grep -Fq 'Usage:' <<<"$no_argument_output" || fail "no-argument usage is missing"
[[ $unknown_status -eq 1 ]] || fail "unknown-option status is not 1"
grep -Fq 'ERROR: Unknown option:' <<<"$unknown_output" || fail "unknown-option error is missing"
for required in /opt/MMDVM_Bridge/MMDVM_Bridge /usr/share/dvswitch/include/functions.php /usr/share/dvswitch/include/status.php /opt/MMDVM_Bridge/dvswitch.sh lib/patch_mmdvm_binary.py; do grep -Fq "$required" "$INSTALLER" || fail "required target or patcher missing: $required"; done
for option in --dry-run --install --restore; do grep -Fq -- "$option" "$INSTALLER" || fail "option missing: $option"; done
grep -Fq -- '--user-agent "DVSwitch"' "$INSTALLER" || fail "RefCheck-compatible user-agent is missing"
if grep -Fq -- '--user-agent "DVSwitch-Mods/' "$INSTALLER"; then fail "unsupported RefCheck user-agent is present"; fi
binary_install_offset=$(grep -boF 'dvsm_install_candidate "$WORK_DIR/MMDVM_Bridge"' "$INSTALLER" | head -n1 | cut -d: -f1)
php_install_offset=$(grep -boF 'dvsm_install_candidate "$WORK_DIR/functions"' "$INSTALLER" | head -n1 | cut -d: -f1)
[[ -n "$binary_install_offset" && -n "$php_install_offset" && $binary_install_offset -lt $php_install_offset ]] || fail "MMDVM binary is not installed before dashboard files"
printf 'Installer tests passed.\n'
