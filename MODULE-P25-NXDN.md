# P25/NXDN dashboard module

Status: test-only; live installation is not enabled yet.

This module adds friendly P25 and NXDN reflector labels to temporary copies of locally installed DVSwitch Dashboard files. It does not contain complete upstream files.

Lookup order is `name`, then `sponsor`, then `TG <number>`. Display text is normalized without truncation and escaped as UTF-8-safe HTML.

The patch engine is idempotent and refuses missing or ambiguous anchors. The main installer will not call it until backup, validation, atomic installation, and rollback tests are complete.
