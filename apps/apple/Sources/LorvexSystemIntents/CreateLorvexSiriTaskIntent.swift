import AppIntents
import Foundation
import LorvexCore

/// Siri's "create a reminder" for Lorvex: creates a task. Siri alone calls it;
/// Shortcuts has ``CaptureLorvexTaskIntent``.
///
/// It runs on a locked device like the capture action, since it only adds a
/// task. Three reminder fields have no place in a task. `locationTrigger` and
/// `section` are declared because the reminder shape requires them, and Siri
/// can never fill them (see ``LorvexSiriLocationTriggerEntity``). `images` can
/// arrive; a task has no attachments, so the task is created without them.
@available(macOS 27.0, iOS 27.0, *)
@AppIntent(schema: .reminders.createReminder)
struct CreateLorvexSiriTaskIntent: LorvexUnauthenticatedIntent {
  static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  static let isAssistantOnly = true

  var title: String
  var list: LorvexSiriListEntity?
  var note: AttributedString?
  var isFlagged: Bool?
  var images: [IntentFile]
  var tags: Set<String>
  var urls: [URL]
  var dueDate: DateComponents?
  var recurrence: Calendar.RecurrenceRule?
  var locationTrigger: LorvexSiriLocationTriggerEntity?
  var section: LorvexSiriSectionEntity?

  func perform() async throws -> some ReturnsValue<LorvexSiriTaskEntity> {
    let fields = SiriTaskFields(
      title: title,
      note: note.map { String($0.characters) },
      tags: tags,
      urls: urls,
      date: dueDate,
      recurrence: recurrence,
      isFlagged: isFlagged,
      listID: list?.id)
    return .result(value: try await LorvexTaskIntentRunner.createSiriTask(fields))
  }
}
