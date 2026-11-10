import Foundation
import LorvexCore

extension MobileStore {
  /// Surfaces the on-disk store's quarantine notice exactly once.
  ///
  /// When the core had to set aside an unreadable / schema-incompatible database
  /// on open and start fresh, the user would otherwise silently get an empty app.
  /// Composes a dismissible message and latches it via
  /// `hasSurfacedDatabaseRecoveryNotice` so it shows once, not on every refresh.
  /// Called from `refresh()` after the core has been opened (so the quarantine
  /// decision is available).
  ///
  /// The notice comes from this process's own open, or, read once per run,
  /// from the fresh database, which remembers a quarantine another process
  /// performed (a widget or Shortcuts action, an earlier run that ended before
  /// the alert) until the user dismisses the alert. `readingStoredNotice` is
  /// false after a failed load, when that read would fail too.
  func surfaceDatabaseRecoveryNoticeIfNeeded(readingStoredNotice: Bool = true) async {
    guard !hasSurfacedDatabaseRecoveryNotice else { return }
    var notice = core.databaseRecoveryNotice
    if notice == nil, readingStoredNotice, !hasReadStoredDatabaseRecoveryNotice {
      hasReadStoredDatabaseRecoveryNotice = true
      notice = await core.pendingDatabaseRecoveryNotice()
    }
    guard let notice, !hasSurfacedDatabaseRecoveryNotice else { return }
    hasSurfacedDatabaseRecoveryNotice = true
    // The backup lives in the app's sandbox container, a path the user can't
    // navigate to on iOS, so the notice states only that the data is preserved.
    let format = String(
      localized: "database.recovery.notice",
      defaultValue: """
        Lorvex couldn’t open your previous database (%1$@), so it was set aside \
        and a fresh one was created. Your earlier data is preserved.
        """, table: "Localizable", bundle: MobileL10n.bundle)
    databaseRecoveryMessage = String(format: format, notice.reason)
  }

  /// The user has read the quarantine notice: close it and stop the fresh
  /// database from raising it again.
  public func dismissDatabaseRecoveryNotice() {
    databaseRecoveryMessage = nil
    let core = core
    Task { await core.acknowledgeDatabaseRecoveryNotice() }
  }
}
