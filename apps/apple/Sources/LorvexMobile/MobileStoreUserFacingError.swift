import Foundation
import LorvexCore

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
          "Lorvex can't access its data storage, so this couldn't be completed. Please restart Lorvex.",
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
    try? await core.appendDiagnosticLog(
      source: "ios.ui.action_failed",
      level: "error",
      message: "A user action failed.",
      details: classification.technicalDetail)
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
      try? await core.appendDiagnosticLog(
        source: source,
        level: "error",
        message: "A user action failed.",
        details: classification.technicalDetail)
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
    try? await core.appendDiagnosticLog(
      source: source,
      level: "error",
      message: "Cloud sync failed.",
      details: classification.technicalDetail)
    if case .unrecoverable = classification.category {
      return UserFacingError.message(for: classification, copy: userFacingErrorCopy)
    }
    return userFacingErrorCopy.somethingWentWrong
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
