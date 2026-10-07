#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Structural tests for the YSF status-card reflector ID display."""

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "ysf_target_id", ROOT / "lib/patch_dashboard_ysf_target_id.py"
)
assert SPEC and SPEC.loader
PATCHER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PATCHER)

fixture = """<?php
                $ysfLinkedToTxt = $ysfLinkedTo;
                        if ((strcasecmp($ysfRoomTxtLine[0], $ysfLinkedTo) == 0) || (strcasecmp($ysfRoomTxtLine[1], $ysfLinkedTo) == 0)) {
                                $ysfLinkedToTxt = $ysfRoomTxtLine[1];
                                break;
                        }
            $ysfLinkedToTxt = str_replace('_', ' ', $ysfLinkedToTxt);
"""
first = PATCHER.patch(fixture)
assert PATCHER.patch(first) == first, "patcher is not idempotent"
assert PATCHER.ID_ASSIGNMENT in first
assert "(ID " in PATCHER.ID_RENDER
assert "htmlspecialchars($ysfLinkedToId" in PATCHER.ID_RENDER
print("PASS: YSF reflector ID is captured and rendered on a safe second line")
