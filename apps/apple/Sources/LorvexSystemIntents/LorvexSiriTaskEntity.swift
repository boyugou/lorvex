import AppIntents
import Foundation
import LorvexCore

/// A Lorvex task in the shape of the system's reminder, the shape Siri works
/// with on macOS 27 and iOS 27. ``LorvexTaskEntity`` is the task the Shortcuts
/// actions take.
///
/// ``SiriTaskMapping`` says how a task's fields fill the reminder's: its one
/// date is the planned day and time, or the deadline of a task with no planned
/// day; a flag is priority P1. A task has no link field, so `urls` is empty,
/// and no location trigger, so `locationTrigger` is nil.
@available(macOS 27.0, iOS 27.0, *)
@AppEntity(schema: .reminders.reminder)
struct LorvexSiriTaskEntity: SyncableEntity {
  static let defaultQuery = LorvexSiriTaskEntityQuery()

  var id: LorvexTask.ID { task.id }
  var title: String { task.title }
  var note: AttributedString? { task.notes.isEmpty ? nil : AttributedString(task.notes) }
  var tags: Set<String> { Set(task.tags) }
  var urls: [URL] { [] }
  var dueDate: DateComponents? {
    SiriTaskMapping.moment(for: task).map(SiriTaskMapping.dateComponents(for:))
  }
  var recurrence: Calendar.RecurrenceRule? {
    task.recurrence.flatMap { SiriTaskMapping.recurrence(for: $0) }
  }
  var isCompleted: Bool { task.status == .completed }
  var isFlagged: Bool? { task.priority == .p1 }
  var creationDate: Date? { SiriTaskMapping.instant(fromTimestamp: task.createdAt) }
  var completionDate: Date? { SiriTaskMapping.instant(fromTimestamp: task.completedAt) }
  var locationTrigger: LorvexSiriLocationTriggerEntity? { nil }
  /// The list the task is in; the Inbox for a task with no list of its own.
  var list: LorvexSiriListEntity

  var task: LorvexTask

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(task.title)",
      subtitle: LorvexTaskStatusOption.localizedLabel(forRawStatus: task.status.rawValue),
      image: .init(systemName: isCompleted ? "checkmark.circle" : "circle"))
  }

  init(task: LorvexTask, list: LorvexSiriListEntity) {
    self.task = task
    self.list = list
  }
}

@available(macOS 27.0, iOS 27.0, *)
struct LorvexSiriTaskEntityQuery: EntityStringQuery {
  func entities(for identifiers: [LorvexSiriTaskEntity.ID]) async throws -> [LorvexSiriTaskEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.entities(for: identifiers, core: core)
    }
  }

  func suggestedEntities() async throws -> [LorvexSiriTaskEntity] {
    try await entities(matching: "")
  }

  func entities(matching string: String) async throws -> [LorvexSiriTaskEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.entities(matching: string, core: core)
    }
  }

  /// Each identifier's task, in the order asked. An identifier whose task no
  /// longer exists is left out; any other failure fails the query.
  static func entities(
    for identifiers: [LorvexSiriTaskEntity.ID], core: any LorvexCoreServicing
  ) async throws -> [LorvexSiriTaskEntity] {
    var tasks: [LorvexTask] = []
    for id in identifiers {
      do {
        tasks.append(try await core.loadTask(id: id))
      } catch LorvexCoreError.taskNotFound {
        continue
      }
    }
    return try await entities(wrapping: tasks, core: core)
  }

  /// The active tasks whose text matches `string`, found by the core's text
  /// index; the first fifty active tasks for a blank string. Completed and
  /// cancelled tasks are left out, as they are for the Shortcuts task
  /// parameter.
  static func entities(
    matching string: String, core: any LorvexCoreServicing
  ) async throws -> [LorvexSiriTaskEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let found =
      query.isEmpty
      ? try await core.listTasks(
        status: "all", listID: nil, priority: nil, text: nil, limit: 50, offset: 0
      ).tasks
      : try await core.searchTasks(query: query, status: "all", limit: 50, offset: 0).tasks
    return try await entities(wrapping: found.filter { $0.status.isActive }, core: core)
  }

  /// `tasks` as entities, each with the list it is in.
  static func entities(
    wrapping tasks: [LorvexTask], core: any LorvexCoreServicing
  ) async throws -> [LorvexSiriTaskEntity] {
    guard !tasks.isEmpty else { return [] }
    let lists = Dictionary(
      try await core.loadLists().lists.map { ($0.id, LorvexSiriListEntity(list: $0)) },
      uniquingKeysWith: { first, _ in first })
    return tasks.map { task in
      let listID = task.listID ?? LorvexListNaming.inboxID
      return LorvexSiriTaskEntity(
        task: task, list: lists[listID] ?? LorvexSiriListEntity(id: listID, name: listID))
    }
  }
}
