# P25/NXDN dashboard module

Status: release candidate for controlled testing on `nodetest`.

This module adds friendly P25 and NXDN reflector labels to temporary copies of locally installed DVSwitch Dashboard files. It does not contain complete upstream files.

Lookup order is `name`, then `sponsor`, then `TG <number>`. Display text is normalized without truncation and escaped as UTF-8-safe HTML.

The patch engine is idempotent and refuses missing or ambiguous anchors. The installer builds temporary candidates, validates them, downloads and validates both JSON databases, creates protected backups, installs atomically, validates the live result, and rolls back automatically on failure.
