#!/usr/bin/env python3
# Version: 1.0.0
"""Regression coverage for recovery after one shared dashboard file rollback."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATCHER = ROOT / "lib" / "patch_dashboard_p25_nxdn.py"
SPEC = importlib.util.spec_from_file_location("patch_dashboard_p25_nxdn", PATCHER)
assert SPEC and SPEC.loader
PATCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PATCH)


class PartialRecoveryTests(unittest.TestCase):
    def test_upgrades_known_previous_helper_without_touching_status(self) -> None:
        functions = "<?php\n" + PATCH.LEGACY_PHP_FUNCTION + PATCH.FUNCTION_ANCHOR + " {}\n"
        status = "<?php\n" + PATCH.P25_WRAPPED + ";\n" + PATCH.NXDN_WRAPPED + ";\n"

        upgraded_functions, upgraded_status = PATCH.patch_text(functions, status)

        self.assertEqual(upgraded_functions.count(PATCH.PHP_FUNCTION), 1)
        self.assertNotIn(PATCH.LEGACY_PHP_FUNCTION, upgraded_functions)
        self.assertEqual(upgraded_status, status)
        self.assertEqual(
            PATCH.patch_text(upgraded_functions, upgraded_status),
            (upgraded_functions, upgraded_status),
        )

    def test_upgrades_known_previous_helper_and_recovers_rolled_back_status(self) -> None:
        functions = "<?php\n" + PATCH.LEGACY_PHP_FUNCTION + PATCH.FUNCTION_ANCHOR + " {}\n"
        status = "<?php\n" + PATCH.P25_PLAIN + ";\n" + PATCH.NXDN_PLAIN + ";\n"

        upgraded_functions, upgraded_status = PATCH.patch_text(functions, status)

        self.assertEqual(upgraded_functions.count(PATCH.PHP_FUNCTION), 1)
        self.assertEqual(upgraded_status.count(PATCH.P25_WRAPPED), 1)
        self.assertEqual(upgraded_status.count(PATCH.NXDN_WRAPPED), 1)

    def test_repairs_only_status_calls_when_helper_is_already_installed(self) -> None:
        functions = "<?php\n" + PATCH.PHP_FUNCTION + PATCH.FUNCTION_ANCHOR + " {}\n"
        status = (
            "<?php\n// Preserve unrelated dashboard customizations\n"
            + PATCH.P25_PLAIN
            + ";\n"
            + PATCH.NXDN_PLAIN
            + ";\n"
        )

        repaired_functions, repaired_status = PATCH.patch_text(functions, status)

        self.assertEqual(repaired_functions, functions)
        self.assertIn("// Preserve unrelated dashboard customizations", repaired_status)
        self.assertEqual(repaired_status.count(PATCH.P25_WRAPPED), 1)
        self.assertEqual(repaired_status.count(PATCH.NXDN_WRAPPED), 1)

    def test_ambiguous_partial_state_is_rejected(self) -> None:
        functions = "<?php\n" + PATCH.PHP_FUNCTION + PATCH.FUNCTION_ANCHOR + " {}\n"
        status = "<?php\n" + PATCH.P25_PLAIN + ";\n"

        with self.assertRaisesRegex(PATCH.PatchError, "ambiguous"):
            PATCH.patch_text(functions, status)

    def test_complete_install_remains_idempotent(self) -> None:
        functions = "<?php\n" + PATCH.FUNCTION_ANCHOR + " {}\n"
        status = "<?php\n" + PATCH.P25_PLAIN + ";\n" + PATCH.NXDN_PLAIN + ";\n"

        installed_functions, installed_status = PATCH.patch_text(functions, status)
        self.assertEqual(
            PATCH.patch_text(installed_functions, installed_status),
            (installed_functions, installed_status),
        )

    def test_reflector_number_is_rendered_below_friendly_name(self) -> None:
        self.assertIn('$numberLine = $hasFriendlyName ? "<br/><span', PATCH.PHP_FUNCTION)
        self.assertIn('(TG ".$number.")</span>', PATCH.PHP_FUNCTION)


if __name__ == "__main__":
    unittest.main()
