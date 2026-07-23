import Foundation

/// Marks CloudSync's reconstructible on-disk cache as excluded from iCloud /
/// Time Machine backup.
///
/// Cached `CKRecord` system fields are reconstructible CloudKit state. Excluding
/// them from backup prevents a restored database from carrying stale record
/// change tags; a cache miss merely takes the normal conflict-reconciliation
/// path and refreshes the tag. Change cursors live transactionally in the managed
/// SQLite database, not in this directory. The CONSENT / account-safety state (the account
/// fingerprint and the pause reason, including `userDeletedZone`) is deliberately
/// NOT routed through here — it must survive a restore so the deletion/adopt
/// gates still hold.
///
/// Best-effort by contract: a failure to set the flag must never fail the sync
/// write it guards, so errors are swallowed.
enum CloudSyncBackupExclusion {
  /// Set `isExcludedFromBackup` on `url` (a directory or file). Excluding a
  /// directory excludes its whole subtree, so this is applied to the cache
  /// directory. Reapplied on each write by the cache stores because an atomic
  /// write (write-temp + rename) that replaces the directory would clear the
  /// flag. Reapplying on an existing, already-excluded directory is a cheap
  /// no-op.
  static func exclude(_ url: URL) {
    var url = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
  }
}
