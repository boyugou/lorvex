import Foundation
import LorvexCore
import OSLog

private let userFacingErrorLog = Logger(
  subsystem: "com.lorvex.mobile", category: "user-facing-error")

extension MobileStore {
  /// Localized copy for the generic error categories, resolved from the
  /// LorvexMobile string catalog. The core classifier stays platform-neutral;
  /// the host supplies the human wording (the `fallbackBody` pattern).
  var userFacingErrorCopy: UserFacingError.Copy {
    UserFacingError.Copy(
      itemNoLongerExists: String(
        localized: "error.item_gone", defaultValue: "That item no longer exists.",
        table: "Localizable", bundle: MobileL10n.bundle),
      somethingWentWrong: String(
        localized: "error.generic", defaultValue: "Something went wrong. Please try again.",
        table: "Localizable", bundle: MobileL10n.bundle),
      storageUnavailable: String(
        localized: "error.storage_unavailable",
        defaultValue:
          "Lorvex can’t access its data storage, so this couldn’t be completed. Please restart Lorvex.",
        table: "Localizable", bundle: MobileL10n.bundle),
      databaseNewer: String(
        localized: "error.database_newer",
        defaultValue:
          "This database was created by a newer version of Lorvex. Please update Lorvex to open it.",
        table: "Localizable", bundle: MobileL10n.bundle))
  }

  /// Present `error` in the root "Something went wrong" alert, mapped through
  /// ``UserFacingError`` so a raw UUID, SQL string, or internal invariant never
  /// reaches the user. Validation messages that are already user-appropriate
  /// pass through; not-found and generic failures show localized copy, and
  /// their raw technical detail is routed to `error_logs` for diagnosis.
  func presentUserFacingError(_ error: Error) async {
    if let recurrenceError = error as? TaskRecurrenceEditorError {
      errorMessage = localizedRecurrenceEditorMessage(recurrenceError)
      return
    }
    let classification = UserFacingError.classify(error)
    errorMessage = UserFacingError.message(for: classification, copy: userFacingErrorCopy)
    guard classification.category != .validation else { return }
    await recordFailure(classification, source: "ios.ui.action_failed", message: "A user action failed.")
  }

  /// Present a failure of the local refresh, which runs without the user
  /// asking (on foreground, after a sync, on a push), in the root alert. The
  /// first occurrence of a message is shown; the same message again is only
  /// logged until a refresh succeeds and clears the latch, so a persistent
  /// failure does not raise the alert on every refresh. A different message is
  /// shown, since it is a new fact. Every occurrence reaches `error_logs`.
  func presentRefreshFailure(_ error: Error) async {
    let classification = UserFacingError.classify(error)
    let message = UserFacingError.message(for: classification, copy: userFacingErrorCopy)
    if message != surfacedRefreshFailureMessage {
      surfacedRefreshFailureMessage = message
      errorMessage = message
    }
    guard classification.category != .validation else { return }
    await recordFailure(classification, source: "ios.refresh_failed", message: "A refresh failed.")
  }

  /// Clear the refresh-failure latch after a successful refresh, dismissing
  /// the alert only when it still shows that refresh failure, so an action's
  /// own error stays up until the user acknowledges it.
  func clearRefreshFailure() {
    if surfacedRefreshFailureMessage != nil, errorMessage == surfacedRefreshFailureMessage {
      errorMessage = nil
    }
    surfacedRefreshFailureMessage = nil
  }

  /// Records a failure's technical detail in the unified log and in
  /// `error_logs`. A storage failure, or one `error_logs` refuses, also goes to
  /// the fallback file: when the store is what fails, `error_logs` cannot be
  /// trusted to hold the row that explains it (its insert is best-effort and
  /// drops a failed write silently).
  func recordFailure(
    _ classification: UserFacingError.Classification, source: String, message: String
  ) async {
    logTechnicalDetail(classification, source: source)
    var recorded = true
    do {
      try await core.appendDiagnosticLog(
        source: source, level: "error", message: message,
        details: classification.technicalDetail)
    } catch {
      recorded = false
    }
    var isStorageFailure = false
    if case .unrecoverable = classification.category { isStorageFailure = true }
    if !recorded || isStorageFailure {
      diagnosticFallback.append(
        source: source, message: message, details: classification.technicalDetail)
    }
  }

  /// Mirrors the `error_logs` routing into the unified log, so a failure whose
  /// root cause is the store itself — which makes `error_logs` unreachable — is
  /// still diagnosable from the device log. The raw detail is public in debug
  /// builds only; release builds keep it private.
  private func logTechnicalDetail(_ classification: UserFacingError.Classification, source: String) {
    let category = String(describing: classification.category)
    #if DEBUG
      userFacingErrorLog.error(
        "\(source, privacy: .public) failed [\(category, privacy: .public)]: \(classification.technicalDetail, privacy: .public)")
    #else
      userFacingErrorLog.error(
        "\(source, privacy: .public) failed [\(category, privacy: .public)]: \(classification.technicalDetail, privacy: .private)")
    #endif
  }

  private func localizedRecurrenceEditorMessage(_ error: TaskRecurrenceEditorError) -> String {
    switch error {
    case .invalidInterval:
      String(
        localized: "recurrence.editor.error.invalid_interval",
        defaultValue: "The recurrence interval must be a whole number from 1 through 10,000.",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .concurrentChange:
      String(
        localized: "recurrence.editor.error.concurrent_change",
        defaultValue:
          "This recurrence changed on another device while you were editing. Review the latest rule and try again.",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  /// Classify `error` for an *inline* banner (not the root alert): route the raw
  /// technical detail to `error_logs` (mirroring ``presentUserFacingError(_:)``)
  /// and return the user-safe message. Surfaces that own their own inline failure
  /// field (the EventKit settings banner, the notification-action toast) call
  /// this so a raw UUID / SQL / invariant never reaches the user while the
  /// diagnostic detail is still captured. `source` tags the diagnostic origin.
  func userFacingBannerMessage(for error: Error, source: String) async -> String {
    let classification = UserFacingError.classify(error)
    if classification.category != .validation {
      await recordFailure(classification, source: source, message: "A user action failed.")
    }
    return UserFacingError.message(for: classification, copy: userFacingErrorCopy)
  }

  /// Classify a raw failure *message string* for an inline banner, mirroring
  /// ``userFacingBannerMessage(for:source:)``. Used where the originating `Error`
  /// was flattened to text before it reached the store — e.g. a
  /// notification-action failure delivered across a `NotificationCenter`
  /// boundary — so the shared classifier can still genericize a raw UUID / SQL /
  /// invariant before it is shown.
  func userFacingBannerMessage(forMessage message: String, source: String) async -> String {
    await userFacingBannerMessage(
      for: MessageBackedError(message: message), source: source)
  }

  /// Return safe copy for a background CloudKit failure while retaining the
  /// exact transport detail in the local diagnostics ring. CloudKit wording is
  /// implementation detail, not validated user copy, so every non-fatal
  /// category deliberately collapses to the generic retry message.
  func cloudSyncUserFacingErrorMessage(for error: Error, source: String) async -> String {
    let classification = UserFacingError.classify(error)
    await recordFailure(classification, source: source, message: "Cloud sync failed.")
    if case .unrecoverable = classification.category {
      return UserFacingError.message(for: classification, copy: userFacingErrorCopy)
    }
    // Append the compact NSError identity so a tester reading the sync status
    // row can report an actionable code ("CKErrorDomain 12") instead of only
    // the generic copy; the full detail is already in the diagnostics log.
    // Swift errors bridge to a "Module.Type" domain that carries no user value,
    // so only genuine framework domains (dot-free) are surfaced.
    let nsError = error as NSError
    guard !nsError.domain.contains(".") else {
      return userFacingErrorCopy.somethingWentWrong
    }
    return "\(userFacingErrorCopy.somethingWentWrong) (\(nsError.domain) \(nsError.code))"
  }

  func cloudSyncUserFacingErrorMessage(forMessage message: String, source: String) async -> String {
    await cloudSyncUserFacingErrorMessage(
      for: MessageBackedError(message: message), source: source)
  }
}

/// Re-wraps a raw failure message string as an `Error` so it can run through the
/// shared ``UserFacingError`` classifier, which keys off a bound message.
private struct MessageBackedError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}
