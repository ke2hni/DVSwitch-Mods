#!/usr/bin/env python3
# Version: 1.0.0
# SPDX-License-Identifier: MIT

"""Regression test that active club licenses use FCC entity names."""
from pathlib import Path
import importlib.util
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("fcc_builder", ROOT / "lib/build_fcc_first_names.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def en_row(system_id, entity, first):
    fields = ["EN", system_id, "1", "N", "", "", "", entity, first, ""]
    return "|".join(fields) + "|\n"


with tempfile.TemporaryDirectory(prefix="fcc-entity-fallback-") as temp:
    root = Path(temp)
    archive = root / "fcc.zip"
    output = root / "database.dat"
    hd = "HD|club-id|1|E|NI6IW|A|\nHD|person-id|1|E|K1ABC|A|\n"
    en = (
        en_row("club-id", "USS MIDWAY CV-41 COMEDTRA", "")
        + en_row("person-id", "DOE, JANE", "JANE")
    )
    with zipfile.ZipFile(archive, "w") as zf:
        zf.writestr("counts", "File Creation Date: 2026-10-10\n2 path/HD.dat\n2 path/EN.dat\n")
        for name in ("AM.dat", "CO.dat", "HS.dat", "LA.dat", "SC.dat", "SF.dat"):
            zf.writestr(name, "")
        zf.writestr("HD.dat", hd)
        zf.writestr("EN.dat", en)

    count = builder.build(archive, output, minimum=2)
    data = output.read_text()
    assert count == 2
    assert "NI6IW     |USS MIDWAY CV-41 COMEDTRA" in data, data
    assert "K1ABC     |Jane" in data, data

print("PASS: FCC builder retains active club entity names and personal first names")
