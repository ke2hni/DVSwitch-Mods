# MMDVM compatibility module

This module does not include or redistribute MMDVM_Bridge. It transforms a temporary copy of the executable already installed on the user's system.

Two fixed-length command strings are supported:

- P25: `TalkGroup%d` becomes `TalkGroup %d`.
- YSF: `Link%c%c%c%05d` becomes `Link%c%c%c %05d`.

Each inserted space consumes an existing trailing NUL padding byte, so the file size and subsequent offsets do not change. The patcher requires exactly one unpatched or exactly one already-patched form of each complete anchor. Missing, duplicate, or mixed ambiguous anchors cause a hard failure before installation.

The installer backs up the local executable, preserves its ownership and mode, installs it before dependent dashboard changes, and restores it automatically if any later stage fails.
