#!/usr/bin/env python3
# Version: 1.0.0
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
assert "(TG " in PATCHER.TG_RENDER
assert "(ID " not in PATCHER.TG_RENDER
assert "htmlspecialchars($ysfLinkedToId" in PATCHER.TG_RENDER
legacy = first.replace(PATCHER.TG_LABEL, PATCHER.ID_LABEL)
assert "(ID " in legacy
upgraded = PATCHER.patch(legacy)
assert "(TG " in upgraded and "(ID " not in upgraded
assert PATCHER.patch(upgraded) == upgraded, "upgraded YSF label is not idempotent"
print("PASS: YSF target number is rendered as TG and previous ID label upgrades safely")
