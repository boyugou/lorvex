import Foundation
import LorvexCore

extension MobileStore {
  /// Surfaces the on-disk store's quarantine notice exactly once.
  ///
  /// When the core had to set aside an unreadable / schema-incompatible database
  /// on open and start fresh, the user would otherwise silently get an empty app.
  /// Composes a dismissible message (reason + backup location) from the core's
  /// `databaseRecoveryNotice` and latches it via `hasSurfacedDatabaseRecoveryNotice`
  /// so it shows once, not on every refresh. Called from `refresh()` after the
  /// core has been opened (so the quarantine decision is available).
  func surfaceDatabaseRecoveryNoticeIfNeeded() {
    guard !hasSurfacedDatabaseRecoveryNotice,
      let notice = core.databaseRecoveryNotice
    else { return }
    hasSurfacedDatabaseRecoveryNotice = true
    // The backup lives in the app's sandbox container, a path the user can't
    // navigate to on iOS, so the notice states only that the data is preserved.
    let format = String(
      localized: "database.recovery.notice",
      defaultValue: """
        Lorvex couldn't open your previous database (%1$@), so it was set aside \
        and a fresh one was created. Your earlier data is preserved.
        """, table: "Localizable", bundle: MobileL10n.bundle)
    databaseRecoveryMessage = String(format: format, notice.reason)
  }
}
