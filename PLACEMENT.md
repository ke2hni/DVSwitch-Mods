# Release placement

Copy the contents of this update archive into the root of the Windows `DVSwitch-Mods` working copy, preserving all directories and replacing matching files.

Keep the existing `.git/` directory. Do not copy upstream DVSwitch files, executables, package files, configuration files, backups, or material from the former `dvswitch-fixes` repository.

Review `git status` before committing. The `Repository checks` workflow must pass without warnings before the release candidate is pulled onto `nodetest`.
