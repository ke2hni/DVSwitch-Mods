#!/usr/bin/env python3
# Version: 1.0.0
# SPDX-License-Identifier: MIT

"""Ensure the FCC check accepts only known-safe installed builder variants."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "mod-dashboard-fcc-first-names.sh").read_text(encoding="utf-8")
start = source.index("builder_matches_supported() {")
end = source.index("\n}\n\nupdater_release_state()", start) + 2
function = source[start:end]

with tempfile.TemporaryDirectory(prefix="fcc-builder-version-") as directory:
    root = Path(directory)
    repository = root / "builder.py"
    installed = root / "installed-builder.py"
    common = "#!/usr/bin/env python3\n# SPDX-License-Identifier: MIT\ndef main():\n    return 0\n"
    repository.write_text("#!/usr/bin/env python3\n# Version: 1.0.0\n# SPDX-License-Identifier: MIT\ndef main():\n    return 0\n")
    installed.write_text(common)

    def matches() -> bool:
        result = subprocess.run(
            ["bash", "-c", function + '\nbuilder_matches_supported "$1" "$2"', "test", str(repository), str(installed)],
            check=False,
        )
        return result.returncode == 0

    assert matches(), "a Version-comment-only difference was rejected"
    current = (ROOT / "lib/build_fcc_first_names.py").read_text(encoding="utf-8")
    entity_function = '''def ascii_entity_name(value: str) -> str:
    """Keep an FCC organization/entity name when no personal first name exists."""
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    value = " ".join(value.strip().split())
    value = "".join(ch for ch in value if ch.isalnum() or ch in " .'-")
    return value[:40].strip()


'''
    previous = current.replace(entity_function, "").replace(
        "first = ascii_name(row[8]) or ascii_entity_name(row[7])",
        "first = ascii_name(row[8])",
    )
    installed.write_text(previous)
    repository.write_text(current)
    assert matches(), "the supported previous builder release was rejected"
    installed.write_text(common.replace("return 0", "return 1"))
    assert not matches(), "a builder code difference was accepted"

print("PASS: FCC builder compatibility accepts version metadata and the supported previous release")
