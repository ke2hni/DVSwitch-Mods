# Release placement

Copy the contents of the release archive into the root of the `DVSwitch-Mods` repository, preserving all directories and replacing matching files.

The archive is a complete repository snapshot except for Git history. Keep `.git/` from the existing clone; do not copy material from the former `dvswitch-fixes` repository.

After committing, the `Repository checks` workflow must pass without warnings before the release candidate is downloaded to `nodetest`.
