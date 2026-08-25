# Transaction framework

Status: integrated into installer release candidate `0.2.0-rc2`.

The transaction library creates unique mode-0700 backup sets, copies targets with their metadata, installs candidates by same-directory atomic replacement, and restores all recorded files in reverse order.

It refuses symbolic-link targets, missing files, duplicate backups, relative backup roots, and unavailable rollback copies.

Each backup contains a protected manifest used by `--restore BACKUP-NAME`. Files that did not exist before installation are recorded and removed during rollback or restore.
