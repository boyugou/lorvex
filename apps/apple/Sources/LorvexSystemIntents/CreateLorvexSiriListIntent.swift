import AppIntents
import LorvexCore

/// Siri's "create a reminder list" for Lorvex: creates a list. Siri alone
/// calls it; Shortcuts has ``CreateLorvexListIntent``.
@available(macOS 27.0, iOS 27.0, *)
@AppIntent(schema: .reminders.createList)
struct CreateLorvexSiriListIntent: LorvexAuthenticatedIntent {
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  static let isAssistantOnly = true

  var type: LorvexSiriListType
  var name: String

  func perform() async throws -> some ReturnsValue<LorvexSiriListEntity> {
    .result(value: try await LorvexTaskIntentRunner.createSiriList(name: name))
  }
}
