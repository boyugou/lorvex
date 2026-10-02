import Foundation
import LorvexCore

extension AppStore {
  /// The copy for the host-supplied error categories: the shared LorvexCore
  /// wording, which the Mac app, the iPhone and iPad app, and Siri and
  /// Shortcuts all present.
  var userFacingErrorCopy: UserFacingError.Copy { .standard }

  /// Present `error` in the modal error alert, mapped through
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
      source: "macos.ui.action_failed",
      level: "error",
      message: "A user action failed.",
      details: classification.technicalDetail)
  }

  /// Present a failure of the local refresh, which runs without the user
  /// asking (on activation, after a sync, on a database change), in the
  /// blocking alert. The first occurrence of a message is shown; the same
  /// message again is only logged until a refresh succeeds and clears the
  /// latch, so a persistent failure does not raise the alert on every refresh.
  /// A different message is shown, since it is a new fact. Every occurrence
  /// reaches `error_logs`.
  func presentRefreshFailure(_ error: Error) async {
    let classification = UserFacingError.classify(error)
    let message = UserFacingError.message(for: classification, copy: userFacingErrorCopy)
    if message != surfacedRefreshFailureMessage {
      surfacedRefreshFailureMessage = message
      errorMessage = message
    }
    guard classification.category != .validation else { return }
    try? await core.appendDiagnosticLog(
      source: "macos.refresh_failed",
      level: "error",
      message: "A refresh failed.",
      details: classification.technicalDetail)
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

  private func localizedRecurrenceEditorMessage(_ error: TaskRecurrenceEditorError) -> String {
    switch error {
    case .invalidInterval:
      String(
        localized: "recurrence.editor.error.invalid_interval",
        defaultValue: "The recurrence interval must be a whole number from 1 through 10,000.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .concurrentChange:
      String(
        localized: "recurrence.editor.error.concurrent_change",
        defaultValue:
          "This recurrence changed on another device while you were editing. Review the latest rule and try again.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  /// Classify `error` for an *inline* banner (not the shared modal alert): return
  /// the user-safe message and route the raw technical detail to `error_logs`,
  /// mirroring ``presentUserFacingError(_:)``. Surfaces that own their own inline
  /// failure banner (command-palette search, Settings export / migration) call
  /// this so a raw UUID, SQL string, or internal invariant never reaches the
  /// user while the diagnostic detail is still captured for support. `source`
  /// tags the diagnostic-log origin.
  func userFacingBannerMessage(for error: Error, source: String) async -> String {
    await userFacingBannerMessage(for: UserFacingError.classify(error), source: source)
  }

  /// Present a failure classified elsewhere — a notification action the app
  /// delegate classified while its typed error was in hand — the same way
  /// ``userFacingBannerMessage(for:source:)`` presents an error: return the
  /// user-safe message and route the technical detail of anything but a
  /// validation failure to `error_logs`.
  func userFacingBannerMessage(
    for classification: UserFacingError.Classification, source: String
  ) async -> String {
    if classification.category != .validation {
      try? await core.appendDiagnosticLog(
        source: source,
        level: "error",
        message: "A user action failed.",
        details: classification.technicalDetail)
    }
    return UserFacingError.message(for: classification, copy: userFacingErrorCopy)
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
