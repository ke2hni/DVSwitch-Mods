#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jeff Milne, KE2HNI
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPAIR="$REPO_ROOT/repair-mmdvm-spacing.sh"
fail() { printf 'TEST FAILURE: %s\n' "$1" >&2; exit 1; }

[[ -f "$REPAIR" ]] || fail "repair installer is missing"
bash -n "$REPAIR" || fail "repair installer failed shell syntax validation"
grep -Fq 'SPDX-License-Identifier: MIT' "$REPAIR" || fail "MIT SPDX identifier is missing"
grep -Fq '/opt/MMDVM_Bridge/MMDVM_Bridge' "$REPAIR" || fail "local target is missing"
grep -Fq 'lib/patch_mmdvm_binary.py' "$REPAIR" || fail "binary patcher is missing"
grep -Fq 'lib/transaction.sh' "$REPAIR" || fail "transaction library is missing"

help_output="$(bash "$REPAIR" --help)"
grep -Fq 'MMDVM spacing repair 0.4.0-dev' <<<"$help_output" || fail "version is missing"
for option in --check --dry-run --install --restore; do grep -Fq -- "$option" "$REPAIR" || fail "option missing: $option"; done

for forbidden in functions.php status.php dvswitch.sh P25Hosts.json NXDNHosts.json patch_p25_nxdn.py curl wget; do if grep -Fq "$forbidden" "$REPAIR"; then fail "unrelated stage reference found: $forbidden"; fi; done

printf 'Standalone MMDVM spacing repair tests passed.\n'
