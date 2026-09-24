#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

"""Exercise the manager's required-database gate after updater warnings."""

from __future__ import annotations

from pathlib import Path
import shlex
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
MANAGER = ROOT / "manage-dvswitch-mods.sh"


OPTIONAL_FEED_ERRORS = (
    "Error, downloaded DCS_Hosts.txt failed DCS validation; keeping existing file\n"
    "Error, downloaded DPlus_Hosts.txt failed DPLUS validation; keeping existing file\n"
    "Error, downloaded DExtra_Hosts.txt failed DEXTRA validation; keeping existing file\n"
)


def run_case(
    functions: str,
    base: Path,
    *,
    missing_required: bool = False,
    updater_status: int = 7,
    updater_output: str = OPTIONAL_FEED_ERRORS,
) -> subprocess.CompletedProcess[str]:
    state = base / "state"
    state.mkdir(parents=True)
    required = [base / "required-a.txt", base / "required-b.txt"]
    updater = base / "fake-updater"
    updater_lines = ["#!/bin/sh"]
    for path in required:
        if not (missing_required and path == required[-1]):
            updater_lines.append(f"printf 'valid data\\n' > {shlex.quote(str(path))}")
    updater_lines.append(f"printf '%s' {shlex.quote(updater_output)}")
    updater_lines.append(f"exit {updater_status}")
    updater.write_text("\n".join(updater_lines) + "\n")
    updater.chmod(0o755)

    setup = "\n".join(
        [
            f"STATE_DIR={shlex.quote(str(state))}",
            f"DATABASE_UPDATE_STAMP={shlex.quote(str(state / 'last-database-update'))}",
            "DATABASE_MIN_INTERVAL=3600",
            f"DVSWITCH_COMMAND={shlex.quote(str(updater))}",
            "RATE_LIMIT_EVIDENCE=()",
            "REQUIRED_DATABASES=("
            + " ".join(shlex.quote(str(path)) for path in required)
            + ")",
            "die() { printf 'ERROR: %s\\n' \"$1\" >&2; exit 1; }",
            "require_regular() { [[ -f \"$1\" && ! -L \"$1\" ]]; }",
            "chown() { :; }",
        ]
    )
    script = "set -Eeuo pipefail\n" + setup + "\n" + functions + "\nensure_databases\n"
    return subprocess.run(["bash", "-c", script], text=True, capture_output=True, check=False)


def main() -> None:
    source = MANAGER.read_text()
    start = source.index("databases_ready() {")
    end = source.index("\ncheck_one() {", start)
    functions = source[start:end]
    if "trap 'report_unexpected_failure" not in source:
        raise AssertionError("unexpected manager failures are not reported to the user")
    if "all applicable DVSwitch-Mods components completed successfully" not in source:
        raise AssertionError("successful full installs do not have a clear completion message")

    with tempfile.TemporaryDirectory(prefix="dvsm-db-warning-test-") as temporary:
        base = Path(temporary)
        for status in (0, 7):
            optional_failure = run_case(
                functions, base / f"optional-{status}", updater_status=status
            )
            if optional_failure.returncode != 0:
                raise AssertionError(optional_failure.stdout + optional_failure.stderr)
            if "optional D-Star feeds (DCS/DPlus/DExtra)" not in optional_failure.stdout:
                raise AssertionError("optional D-Star validation errors were not clearly reported")

        missing = run_case(functions, base / "missing", missing_required=True)
        if missing.returncode == 0:
            raise AssertionError("manager continued despite a missing required database")
        if "Database update did not produce a valid regular nonempty file" not in missing.stderr:
            raise AssertionError(missing.stdout + missing.stderr)

        unexpected = run_case(
            functions,
            base / "unexpected",
            updater_status=7,
            updater_output="Unexpected updater failure\n",
        )
        if unexpected.returncode == 0:
            raise AssertionError("manager continued after an unclassified updater failure")
        if "without a recognized optional-feed warning" not in unexpected.stderr:
            raise AssertionError(unexpected.stdout + unexpected.stderr)

    print("PASS: optional-feed warnings continue with valid required data; other failures stop clearly")


if __name__ == "__main__":
    main()
