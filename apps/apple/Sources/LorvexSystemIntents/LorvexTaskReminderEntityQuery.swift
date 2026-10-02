import AppIntents
import Foundation
import LorvexCore

struct LorvexTaskReminderEntityQuery: EntityQuery, EntityStringQuery {
  /// How far ahead suggestions look: the reminders of the next 60 days.
  static let suggestionHorizonHours = 24 * 60

  func entities(for identifiers: [LorvexTaskReminderEntity.ID]) async throws
    -> [LorvexTaskReminderEntity]
  {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.entities(for: identifiers, core: core)
    }
  }

  func suggestedEntities() async throws -> [LorvexTaskReminderEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.suggestedEntities(core: core)
    }
  }

  func entities(matching string: String) async throws -> [LorvexTaskReminderEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.entities(matching: string, core: core)
    }
  }

  /// Each identifier's reminder, read from its own task. An identifier whose
  /// task or reminder no longer exists is left out.
  static func entities(
    for identifiers: [LorvexTaskReminderEntity.ID],
    core: any LorvexCoreServicing
  ) async throws -> [LorvexTaskReminderEntity] {
    let timeZoneIdentifier = try await core.getSessionContext().timezone
    var tasks: [LorvexTask.ID: LorvexTask] = [:]
    var entities: [LorvexTaskReminderEntity] = []
    for identifier in identifiers {
      guard let parts = LorvexTaskReminderEntity.components(of: identifier) else { continue }
      if tasks[parts.taskID] == nil {
        tasks[parts.taskID] = try? await core.loadTask(id: parts.taskID)
      }
      guard let task = tasks[parts.taskID],
        let reminder = task.reminders.first(where: { $0.id == parts.reminderID })
      else { continue }
      entities.append(
        LorvexTaskReminderEntity(
          reminder: reminder, task: task, timeZoneIdentifier: timeZoneIdentifier))
    }
    return entities
  }

  /// The reminders still to fire over the next 60 days, soonest first.
  static func suggestedEntities(core: any LorvexCoreServicing) async throws
    -> [LorvexTaskReminderEntity]
  {
    let timeZoneIdentifier = try await core.getSessionContext().timezone
    return try await core.getUpcomingTaskReminders(hoursAhead: suggestionHorizonHours, limit: 200)
      .map { LorvexTaskReminderEntity(reminder: $0, timeZoneIdentifier: timeZoneIdentifier) }
  }

  /// `reminders` as entities, each titled in the configured time zone.
  static func entities(
    from reminders: [TaskReminderWithTask],
    core: any LorvexCoreServicing
  ) async throws -> [LorvexTaskReminderEntity] {
    let timeZoneIdentifier = try await LorvexIntentFailure.rewording(core: core) {
      try await core.getSessionContext().timezone
    }
    return reminders.map {
      LorvexTaskReminderEntity(reminder: $0, timeZoneIdentifier: timeZoneIdentifier)
    }
  }

  /// Suggested reminders whose task title contains `string`.
  static func entities(
    matching string: String,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexTaskReminderEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let entities = try await suggestedEntities(core: core)
    guard !query.isEmpty else { return entities }
    return entities.filter { $0.taskTitle.localizedStandardContains(query) }
  }
}
