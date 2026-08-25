# Transaction framework

Status: tested library; not connected to live installation yet.

The transaction library creates unique mode-0700 backup sets, copies targets with their metadata, installs candidates by same-directory atomic replacement, and restores all recorded files in reverse order.

It refuses symbolic-link targets, missing files, duplicate backups, relative backup roots, and unavailable rollback copies.
