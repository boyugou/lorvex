import AppIntents
import Foundation
import LorvexCore

/// Siri's "delete reminders" for Lorvex: cancels the tasks after the person
/// confirms. Siri alone calls it; Shortcuts has ``CancelLorvexTaskIntent``.
///
/// A delete through Siri cancels and does not destroy: the tasks stay where
/// they can be reopened. A repeating task stops repeating.
@available(macOS 27.0, iOS 27.0, *)
@AppIntent(schema: .reminders.deleteReminders)
struct DeleteLorvexSiriTasksIntent: DeleteIntent, LorvexAuthenticatedIntent {
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  static let isAssistantOnly = true

  var entities: [LorvexSiriTaskEntity]

  func perform() async throws -> some IntentResult {
    guard !entities.isEmpty else { return .result() }
    let titles = entities.map(\.title).formatted(.list(type: .and))
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.cancel_tasks",
          defaultValue: "Cancel \(titles)? A repeating task will stop repeating.",
          table: "Localizable", bundle: SystemL10n.bundle)))
    _ = try await LorvexTaskIntentRunner.cancelSiriTasks(ids: entities.map(\.id))
    return .result()
  }
}
