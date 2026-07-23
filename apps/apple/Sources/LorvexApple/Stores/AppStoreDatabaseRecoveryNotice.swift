import Foundation
import LorvexCore

extension AppStore {
  /// Surfaces the on-disk store's quarantine notice exactly once.
  ///
  /// When the core had to set aside an unreadable / schema-incompatible database
  /// on open and start fresh, the user would otherwise silently get an empty app.
  /// Composes a dismissible message (reason + backup location) from the core's
  /// `databaseRecoveryNotice` and latches it via `hasSurfacedDatabaseRecoveryNotice`
  /// so it shows once, not on every refresh. Called from the refresh fan-out
  /// after the core has been opened (so the quarantine decision is available).
  func surfaceDatabaseRecoveryNoticeIfNeeded() {
    guard !hasSurfacedDatabaseRecoveryNotice,
      let notice = core.databaseRecoveryNotice
    else { return }
    hasSurfacedDatabaseRecoveryNotice = true
    databaseRecoveryMessage = String(
      format: String(
        localized: "database.recovery.notice",
        defaultValue: """
          Lorvex couldn't open your previous database (%1$@), so it was set aside \
          at %2$@ and a fresh one was created. Your earlier data is preserved there.
          """,
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      notice.reason, notice.backupPath)
  }
}
