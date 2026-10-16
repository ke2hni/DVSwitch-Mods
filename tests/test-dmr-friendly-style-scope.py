#!/usr/bin/env python3
"""Ensure the DMR style check ignores the same style on unrelated dashboard rows."""

from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = (ROOT / "mod-dmr-friendly-names.sh").read_text(encoding="utf-8")
STYLE = "white-space:normal;word-break:normal;overflow-wrap:anywhere;text-align:center;"
DMR_CALL = "dvsModsDmrMasterDisplay($dmrMasterHost, $abinfo)"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def accepts_dmr_row(contents: str) -> bool:
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as source:
        source.write(contents)
        path = source.name
    try:
        result = subprocess.run(
            [
                "bash",
                "-o",
                "pipefail",
                "-c",
                "grep -F 'dvsModsDmrMasterDisplay($dmrMasterHost, $abinfo)' \"$1\" "
                "| grep -Fq 'white-space:normal;word-break:normal;overflow-wrap:anywhere;text-align:center;'",
                "test-dmr-style",
                path,
            ],
            check=False,
        )
        return result.returncode == 0
    finally:
        Path(path).unlink()


def main() -> None:
    require(
        "grep -F 'dvsModsDmrMasterDisplay($dmrMasterHost, $abinfo)' \"$TARGET\" | grep -Fq 'white-space:normal;word-break:normal;overflow-wrap:anywhere;text-align:center;'" in INSTALLER,
        "DMR verifier does not scope the wrapping-style check to its display row",
    )
    require(
        "grep -Fc 'white-space:normal;word-break:normal;overflow-wrap:anywhere;text-align:center;' \"$TARGET\"" not in INSTALLER,
        "DMR verifier still counts matching styles across the full shared status.php",
    )
    fixture = (
        '<tr><td><span style="' + STYLE + '">' + DMR_CALL + "</span></td></tr>\n"
        '<tr><td><span style="' + STYLE + '">(TG 123)</span></td></tr>\n'
    )
    require(accepts_dmr_row(fixture), "DMR row was rejected when YSF also uses the same style")
    unrelated_only = '<tr><td><span style="' + STYLE + '">(TG 123)</span></td></tr>\n'
    require(not accepts_dmr_row(unrelated_only), "style on an unrelated row satisfied the DMR check")
    print("PASS: DMR wrapping-style verification is scoped to the DMR row")


if __name__ == "__main__":
    main()
