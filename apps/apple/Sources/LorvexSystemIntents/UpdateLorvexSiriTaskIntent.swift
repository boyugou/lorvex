import AppIntents
import Foundation
import LorvexCore

/// Siri's "update a reminder" for Lorvex: changes the fields of a task that
/// the request names, completes it, or reopens it. Siri alone calls it;
/// Shortcuts has ``UpdateLorvexTaskIntent`` and the lifecycle actions.
///
/// `locationTrigger` is declared because the reminder shape requires it; Siri
/// can never fill it (see ``LorvexSiriLocationTriggerEntity``).
@available(macOS 27.0, iOS 27.0, *)
@AppIntent(schema: .reminders.updateReminder)
struct UpdateLorvexSiriTaskIntent: LorvexAuthenticatedIntent {
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  static let isAssistantOnly = true

  var target: LorvexSiriTaskEntity
  var title: String?
  var note: AttributedString?
  var tags: Set<String>?
  var urls: [URL]?
  var dueDate: DateComponents?
  var recurrence: Calendar.RecurrenceRule?
  var isCompleted: Bool?
  var isFlagged: Bool?
  var list: LorvexSiriListEntity?
  var locationTrigger: LorvexSiriLocationTriggerEntity?

  func perform() async throws -> some ReturnsValue<LorvexSiriTaskEntity> {
    let fields = SiriTaskFields(
      title: title,
      note: note.map { String($0.characters) },
      tags: tags,
      urls: urls ?? [],
      date: dueDate,
      recurrence: recurrence,
      isCompleted: isCompleted,
      isFlagged: isFlagged,
      listID: list?.id)
    return .result(
      value: try await LorvexTaskIntentRunner.updateSiriTask(id: target.id, fields: fields))
  }
}
