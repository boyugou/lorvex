# Optimizing Your App's Data for iCloud Backup

Source: [Optimizing your app's data for iCloud Backup](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup)

Last verified: 2026-07-10

## Apple Contract

- Application Support is included in normal device backups.
- Reconstructible files should be placed in a purgeable directory when
  appropriate or marked with `isExcludedFromBackup` when they must remain local.
- User-created data that is difficult or impossible to recreate should remain
  eligible for backup.
- File operations can reset exclusion metadata, so an app must reapply it when
  saving.
- Exclusion is guidance, not a guarantee; restore logic must remain safe even if
  an excluded item reappears.

## Lorvex Mapping

The managed SQLite database is user data and belongs in backup. It is also the
sole authority for CloudKit traversal progress and change tokens, so a cursor can
never be restored independently of the database it describes.

Separate `CloudSyncState` files have two explicit lifecycles:

- reconstructible CKRecord system fields live in `Cache/`, which is marked
  `isExcludedFromBackup` by the factory and again on every cache write; and
- the last account fingerprint plus the revisioned safety/consent pause state
  remain in the backup-eligible parent directory.

## Audit Conclusion

Resolved in the 2026-07-16 recovery-state checkpoint. The implementation now
matches the lifecycle split above, and tests pin both cache exclusion and
backup eligibility of account/consent state. Restore/account-boundary behavior
is additionally fenced by the SQLite account binding, physical database
instance identity and explicit account-adoption capability.
