import AppIntents
import Foundation
import LorvexCore

/// One reminder of a Lorvex task, as Siri and Shortcuts pick it: when it
/// fires, with the task it belongs to underneath.
///
/// The identifier joins the task's ID and the reminder's ID (see
/// ``identifier(taskID:reminderID:)``), so a saved shortcut finds its reminder
/// again by reading that one task.
struct LorvexTaskReminderEntity: AppEntity, Identifiable {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.entity.task_reminder.type", defaultValue: "Lorvex Task Reminder", table: "Localizable", bundle: SystemL10n.bundle))
  static let defaultQuery = LorvexTaskReminderEntityQuery()

  var id: String
  var taskID: LorvexTask.ID
  var reminderID: TaskReminder.ID
  /// The UTC timestamp the reminder fires at.
  var reminderAt: String
  var taskTitle: String
  /// The identifier of Lorvex's configured time zone, in which the reminder's
  /// day and clock time are shown, as the app shows them.
  var timeZoneIdentifier: String

  var displayRepresentation: DisplayRepresentation {
    let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
    let when = TaskReminderDateTime.displayString(reminderAt: reminderAt, timeZone: timeZone)
    return DisplayRepresentation(
      title: "\(when)",
      subtitle: "\(taskTitle)",
      image: .init(systemName: "bell")
    )
  }

  init(
    taskID: LorvexTask.ID, reminderID: TaskReminder.ID, reminderAt: String, taskTitle: String,
    timeZoneIdentifier: String
  ) {
    self.id = Self.identifier(taskID: taskID, reminderID: reminderID)
    self.taskID = taskID
    self.reminderID = reminderID
    self.reminderAt = reminderAt
    self.taskTitle = taskTitle
    self.timeZoneIdentifier = timeZoneIdentifier
  }

  init(reminder: TaskReminder, task: LorvexTask, timeZoneIdentifier: String) {
    self.init(
      taskID: task.id, reminderID: reminder.id, reminderAt: reminder.reminderAt,
      taskTitle: task.title, timeZoneIdentifier: timeZoneIdentifier)
  }

  init(reminder: TaskReminderWithTask, timeZoneIdentifier: String) {
    self.init(
      taskID: reminder.taskID, reminderID: reminder.id, reminderAt: reminder.reminderAt,
      taskTitle: reminder.taskTitle, timeZoneIdentifier: timeZoneIdentifier)
  }

  /// `taskID/reminderID`. Lorvex IDs are hyphenated UUIDs, so the slash never
  /// occurs inside either half.
  static func identifier(taskID: LorvexTask.ID, reminderID: TaskReminder.ID) -> String {
    "\(taskID)/\(reminderID)"
  }

  /// The task and reminder IDs an identifier joins, or nil for text that is
  /// not one.
  static func components(of identifier: String) -> (taskID: LorvexTask.ID, reminderID: TaskReminder.ID)? {
    let parts = identifier.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
    return (String(parts[0]), String(parts[1]))
  }
}
