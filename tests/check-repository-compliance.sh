#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

report_failure() {
    printf 'COMPLIANCE ERROR: %s\n' "$1" >&2
    FAILURES=$((FAILURES + 1))
}

while IFS= read -r -d '' relative_path; do
    tracked_file="$REPO_ROOT/$relative_path"
    base_name="$(basename "$relative_path")"

    case "$base_name" in
        MMDVM_Bridge*|Analog_Bridge*|P25Gateway*|NXDNGateway*|YSFGateway*|functions.php|status.php|dvswitch.sh)
            report_failure "prohibited upstream file: $relative_path"
            ;;
    esac

    case "$base_name" in
        *.ini|*.deb|*.rpm|*.so|*.a|*.o|*.bin|*.elf|*.exe|*.bak|*.backup|*.orig|*.rej)
            report_failure "prohibited file type: $relative_path"
            ;;
    esac

    if [[ -f "$tracked_file" ]]; then
        file_description="$(file -b "$tracked_file")"
        case "$file_description" in
            *ELF*|*PE32*|*"shared object"*|*"current ar archive"*|*"Debian binary package"*|*RPM*)
                report_failure "compiled or packaged binary: $relative_path ($file_description)"
                ;;
        esac

        if grep -Iq . "$tracked_file" && grep -Eq -- '-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----' "$tracked_file"; then
            report_failure "private key material detected: $relative_path"
        fi
    fi
done < <(git -C "$REPO_ROOT" ls-files -z)

if ((FAILURES > 0)); then
    printf 'Repository compliance check failed with %d problem(s).\n' "$FAILURES" >&2
    exit 1
fi

printf 'Repository compliance check passed.\n'
