#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$REPO_ROOT/install-dvswitch-mods.sh"

fail() {
    printf 'TEST FAILURE: %s\n' "$1" >&2
    exit 1
}

[[ -f "$INSTALLER" ]] || fail "installer is missing"
bash -n "$INSTALLER" || fail "installer failed shell syntax validation"

grep -Fq 'SPDX-License-Identifier: MIT' "$INSTALLER" || fail "MIT SPDX identifier is missing"
grep -Fq 'Copyright (c) 2026 Jeff Milne, KE2HNI' "$INSTALLER" || fail "copyright notice is missing"

help_output="$(bash "$INSTALLER" --help)"
grep -Fq 'DVSwitch Mods installer 0.2.0-rc1' <<<"$help_output" || fail "version is missing from help output"
grep -Fq 'Usage:' <<<"$help_output" || fail "usage text is missing"

set +e
no_argument_output="$(bash "$INSTALLER" 2>&1)"
no_argument_status=$?
unknown_output="$(bash "$INSTALLER" --not-a-real-option 2>&1)"
unknown_status=$?
set -e

[[ $no_argument_status -eq 2 ]] || fail "running without arguments did not return status 2"
grep -Fq 'Usage:' <<<"$no_argument_output" || fail "running without arguments did not display usage"
[[ $unknown_status -eq 1 ]] || fail "unknown option did not return status 1"
grep -Fq 'ERROR: Unknown option:' <<<"$unknown_output" || fail "unknown option did not display an error"

grep -Fq '/usr/share/dvswitch/include/functions.php' "$INSTALLER" || fail "functions.php target is missing"
grep -Fq '/usr/share/dvswitch/include/status.php' "$INSTALLER" || fail "status.php target is missing"
grep -Fq '/opt/MMDVM_Bridge/dvswitch.sh' "$INSTALLER" || fail "dvswitch.sh target is missing"
grep -Fq -- '--dry-run' "$INSTALLER" || fail "dry-run option is missing"
grep -Fq -- '--install' "$INSTALLER" || fail "install option is missing"
grep -Fq -- '--restore' "$INSTALLER" || fail "restore option is missing"

printf 'Installer tests passed.\n'
