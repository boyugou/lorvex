import Foundation
import LorvexDomain

/// Proves that public-v1's portable task document and exact Apple-native graph
/// are two representations of the same user data. Native-only sync/register
/// history is deliberately excluded; every overlapping user-visible field and
/// child collection is compared after the same normalization the exporter uses.
enum BackupV1TaskProjectionConsistency {
  struct Mismatch: LocalizedError, Equatable {
    let detail: String

    var errorDescription: String? {
      "The portable tasks and native task graph disagree: \(detail)"
    }
  }

  private struct TaskProjection: Equatable {
    let id: String
    let title: String
    let body: String?
    let rawInput: String?
    let aiNotes: String?
    let status: String
    let listID: String
    let priority: String
    let dueDate: String?
    let plannedDate: String?
    let availableFrom: String?
    let estimatedMinutes: Int?
    let recurrence: String?
    let recurrenceExceptions: [String]
    let dependencies: [String]
    let tags: [String]
    let checklist: [ChecklistProjection]
    let reminders: [ReminderProjection]
    let deferCount: Int
    let lastDeferReason: String?
    let lastDeferredAt: String?
    let completedAt: String?
    let createdAt: String?
    let updatedAt: String?
    let archivedAt: String?
  }

  private struct ChecklistProjection: Equatable, Comparable {
    let id: String
    let position: Int
    let text: String
    let completedAt: String?
    let createdAt: String?
    let updatedAt: String?

    static func < (lhs: Self, rhs: Self) -> Bool {
      (lhs.position, lhs.id) < (rhs.position, rhs.id)
    }
  }

  private struct ReminderProjection: Equatable, Comparable {
    let id: String
    let reminderAt: String
    let dismissedAt: String?
    let cancelledAt: String?
    let createdAt: String?
    let originalLocalTime: String?
    let originalTimeZone: String?

    static func < (lhs: Self, rhs: Self) -> Bool {
      (lhs.id, lhs.reminderAt) < (rhs.id, rhs.reminderAt)
    }
  }

  static func validate(
    portableTasks: [ExportTask], nativeGraph: NativeTaskGraphSnapshot,
    portableTags: [ExportTag]? = nil
  ) throws {
    let portableByID = try uniquePortableTasks(portableTasks)
    let nativeByID = try uniqueNativeTasks(nativeGraph.tasks)
    guard Set(portableByID.keys) == Set(nativeByID.keys) else {
      throw Mismatch(detail: "the task identity sets differ")
    }

    let tagNamesByID = portableTags.map { tags in
      Dictionary(tags.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
    }
    if let portableTags {
      let uniqueTagIDs = Set(portableTags.map(\.id))
      guard uniqueTagIDs.count == portableTags.count else {
        throw Mismatch(detail: "the portable tag category repeats an identity")
      }
    }

    let nativeExceptions = try groupedUnique(
      nativeGraph.recurrenceExceptions.map { ($0.taskID, $0.exceptionDate) },
      label: "native recurrence exception")
    let nativeDependencies = try groupedUnique(
      nativeGraph.dependencyEdges.map { ($0.taskID, $0.dependsOnTaskID) },
      label: "native dependency")
    let nativeTagIDs = try groupedUnique(
      nativeGraph.tagEdges.map { ($0.taskID, $0.tagID) }, label: "native task tag")
    let nativeChecklist = try nativeChecklistByTask(nativeGraph.checklistItems)
    let nativeReminders = try nativeRemindersByTask(nativeGraph.reminders)

    for id in portableByID.keys.sorted() {
      guard let portable = portableByID[id], let native = nativeByID[id] else {
        throw Mismatch(detail: "task \(id) disappeared during projection")
      }
      let portableProjection = try portableProjection(
        portable, compareTagNames: tagNamesByID != nil)
      let nativeProjection = try nativeProjection(
        native,
        recurrenceExceptions: nativeExceptions[id] ?? [],
        dependencies: nativeDependencies[id] ?? [],
        tagIDs: nativeTagIDs[id] ?? [],
        tagNamesByID: tagNamesByID,
        checklist: nativeChecklist[id] ?? [],
        reminders: nativeReminders[id] ?? [])

      guard portableProjection == nativeProjection else {
        throw Mismatch(detail: "task \(id) has different overlapping semantic content")
      }
    }
  }

  /// A task-only partial backup cannot prove which portable tag name belongs to
  /// a native tag UUID. It may still validate that both projections carry the
  /// same number of edges, but exact ID-preserving restore would make the result
  /// depend on unrelated rows already present in the destination. Force that
  /// shape through the portable name-based path instead.
  static func permitsExactNativeRestore(
    portableTags: [ExportTag]?, nativeGraph: NativeTaskGraphSnapshot
  ) -> Bool {
    portableTags != nil || nativeGraph.tagEdges.isEmpty
  }

  private static func portableProjection(
    _ task: ExportTask, compareTagNames: Bool
  ) throws -> TaskProjection {
    let priority: String
    guard ["P1", "P2", "P3"].contains(task.priority) else {
      throw Mismatch(detail: "task \(task.id) has unknown portable priority \(task.priority)")
    }
    priority = task.priority

    var dependencies = task.dependsOn ?? []
    try requireUnique(dependencies, label: "portable dependency", taskID: task.id)
    dependencies.sort()

    var exceptions = try (task.recurrenceExceptions ?? []).map { value in
      guard BackupV1NativeTaskGraphSemantics.isCanonicalDate(value) else {
        throw Mismatch(
          detail: "task \(task.id) has invalid portable recurrence exception \(value)")
      }
      return value
    }
    try requireUnique(exceptions, label: "portable recurrence exception", taskID: task.id)
    exceptions.sort()

    var tags = task.tags ?? []
    try requireUnique(tags, label: "portable task tag", taskID: task.id)
    tags.sort()
    if !compareTagNames {
      tags = Array(repeating: "<unmapped-tag>", count: tags.count)
    }

    let checklist = try (task.checklist ?? []).map { item -> ChecklistProjection in
      guard let id = item.id, let position = item.position else {
        throw Mismatch(
          detail: "task \(task.id) has a portable checklist item without exact identity/position")
      }
      guard item.completed == (item.completedAt != nil) else {
        throw Mismatch(
          detail: "task \(task.id) checklist item \(id) disagrees about completion")
      }
      return ChecklistProjection(
        id: id, position: position, text: item.text, completedAt: item.completedAt,
        createdAt: item.createdAt, updatedAt: item.updatedAt)
    }.sorted()
    try requireUnique(checklist.map(\.id), label: "portable checklist", taskID: task.id)

    let reminders = (task.reminders ?? []).map {
      ReminderProjection(
        id: $0.id, reminderAt: $0.reminderAt, dismissedAt: $0.dismissedAt,
        cancelledAt: $0.cancelledAt, createdAt: $0.createdAt,
        originalLocalTime: $0.originalLocalTime, originalTimeZone: $0.originalTz)
    }.sorted()
    try requireUnique(reminders.map(\.id), label: "portable reminder", taskID: task.id)

    return TaskProjection(
      id: task.id, title: task.title, body: normalizedBody(task.notes),
      rawInput: task.rawInput, aiNotes: task.aiNotes, status: task.status,
      listID: task.listID ?? "inbox", priority: priority,
      dueDate: try normalizedPortableDate(task.dueDate, taskID: task.id, field: "dueDate"),
      plannedDate: try normalizedPortableDate(
        task.plannedDate, taskID: task.id, field: "plannedDate"),
      availableFrom: try normalizedPortableDate(
        task.availableFrom, taskID: task.id, field: "availableFrom"),
      estimatedMinutes: task.estimatedMinutes,
      recurrence: try normalizedPortableRecurrence(task.recurrence, taskID: task.id),
      recurrenceExceptions: exceptions, dependencies: dependencies, tags: tags,
      checklist: checklist, reminders: reminders, deferCount: task.deferCount ?? 0,
      lastDeferReason: task.lastDeferReason, lastDeferredAt: task.lastDeferredAt,
      completedAt: task.completedAt, createdAt: task.createdAt,
      updatedAt: task.updatedAt, archivedAt: task.archivedAt)
  }

  private static func nativeProjection(
    _ task: NativeTaskSnapshot, recurrenceExceptions: [String], dependencies: [String],
    tagIDs: [String], tagNamesByID: [String: String]?,
    checklist: [ChecklistProjection], reminders: [ReminderProjection]
  ) throws -> TaskProjection {
    let priority: String
    if let tier = task.priority {
      switch tier {
      case 1: priority = "P1"
      case 2: priority = "P2"
      case 3: priority = "P3"
      default: throw Mismatch(detail: "task \(task.id) has an invalid native priority")
      }
    } else {
      // The portable task model has no "unset" priority and exports SQLite NULL
      // as the neutral P2 display value.
      priority = "P2"
    }

    let tags: [String]
    if let tagNamesByID {
      tags = try tagIDs.map { tagID in
        guard let name = tagNamesByID[tagID] else {
          throw Mismatch(
            detail: "task \(task.id) references tag \(tagID) absent from the portable tag category")
        }
        return name
      }.sorted()
    } else {
      // A task-only partial backup can recreate tags by portable display name
      // but cannot prove the native ID/name mapping. Cardinality still catches
      // dropped or fabricated edges without inventing an equivalence.
      tags = Array(repeating: "<unmapped-tag>", count: tagIDs.count)
    }

    return TaskProjection(
      id: task.id, title: task.title, body: normalizedBody(task.body),
      rawInput: task.rawInput, aiNotes: task.aiNotes, status: task.status,
      listID: task.listID, priority: priority, dueDate: task.dueDate,
      plannedDate: task.plannedDate, availableFrom: task.availableFrom,
      estimatedMinutes: task.estimatedMinutes,
      recurrence: try normalizedNativeRecurrence(task.recurrence, taskID: task.id),
      recurrenceExceptions: recurrenceExceptions, dependencies: dependencies,
      tags: tagNamesByID == nil
        ? Array(repeating: "<unmapped-tag>", count: tagIDs.count) : tags,
      checklist: checklist, reminders: reminders, deferCount: task.deferCount,
      lastDeferReason: task.lastDeferReason, lastDeferredAt: task.lastDeferredAt,
      completedAt: task.completedAt, createdAt: task.createdAt,
      updatedAt: task.updatedAt, archivedAt: task.archivedAt)
  }

  private static func uniquePortableTasks(_ tasks: [ExportTask]) throws -> [String: ExportTask] {
    var result: [String: ExportTask] = [:]
    for task in tasks {
      guard result.updateValue(task, forKey: task.id) == nil else {
        throw Mismatch(detail: "the portable task projection repeats \(task.id)")
      }
    }
    return result
  }

  private static func uniqueNativeTasks(
    _ tasks: [NativeTaskSnapshot]
  ) throws -> [String: NativeTaskSnapshot] {
    var result: [String: NativeTaskSnapshot] = [:]
    for task in tasks {
      guard result.updateValue(task, forKey: task.id) == nil else {
        throw Mismatch(detail: "the native task graph repeats \(task.id)")
      }
    }
    return result
  }

  private static func groupedUnique(
    _ values: [(String, String)], label: String
  ) throws -> [String: [String]] {
    var seen = Set<String>()
    var grouped: [String: [String]] = [:]
    for (owner, value) in values {
      guard seen.insert("\(owner)\u{0}\(value)").inserted else {
        throw Mismatch(detail: "the \(label) collection repeats \(owner):\(value)")
      }
      grouped[owner, default: []].append(value)
    }
    for owner in Array(grouped.keys) { grouped[owner]?.sort() }
    return grouped
  }

  private static func nativeChecklistByTask(
    _ items: [NativeTaskChecklistItemSnapshot]
  ) throws -> [String: [ChecklistProjection]] {
    var seen = Set<String>()
    var result: [String: [ChecklistProjection]] = [:]
    for item in items {
      guard seen.insert(item.id).inserted else {
        throw Mismatch(detail: "the native checklist repeats \(item.id)")
      }
      result[item.taskID, default: []].append(
        ChecklistProjection(
          id: item.id, position: item.position, text: item.text,
          completedAt: item.completedAt, createdAt: item.createdAt,
          updatedAt: item.updatedAt))
    }
    for owner in Array(result.keys) { result[owner]?.sort() }
    return result
  }

  private static func nativeRemindersByTask(
    _ reminders: [NativeTaskReminderSnapshot]
  ) throws -> [String: [ReminderProjection]] {
    var seen = Set<String>()
    var result: [String: [ReminderProjection]] = [:]
    for reminder in reminders {
      guard seen.insert(reminder.id).inserted else {
        throw Mismatch(detail: "the native reminder collection repeats \(reminder.id)")
      }
      result[reminder.taskID, default: []].append(
        ReminderProjection(
          id: reminder.id, reminderAt: reminder.reminderAt,
          dismissedAt: reminder.dismissedAt, cancelledAt: reminder.cancelledAt,
          createdAt: reminder.createdAt, originalLocalTime: reminder.originalLocalTime,
          originalTimeZone: reminder.originalTimeZone))
    }
    for owner in Array(result.keys) { result[owner]?.sort() }
    return result
  }

  private static func normalizedBody(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
  }

  private static func normalizedPortableDate(
    _ value: String?, taskID: String, field: String
  ) throws -> String? {
    guard let value else { return nil }
    guard let date = BackupV1NativeTaskGraphSemantics.portableTaskDate(value) else {
      throw Mismatch(detail: "task \(taskID) has invalid portable \(field)")
    }
    return date
  }

  private static func normalizedPortableRecurrence(
    _ recurrence: ExportRecurrenceRule?, taskID: String
  ) throws -> String? {
    guard let recurrence else { return nil }
    var object: [String: JSONValue] = ["FREQ": .string(recurrence.freq)]
    if let interval = recurrence.interval { object["INTERVAL"] = .int(Int64(interval)) }
    if let byDay = recurrence.byDay {
      object["BYDAY"] = .array(byDay.map(JSONValue.string))
    }
    if let byMonth = recurrence.byMonth {
      object["BYMONTH"] = .array(byMonth.map { .int(Int64($0)) })
    }
    if let byMonthDay = recurrence.byMonthDay {
      object["BYMONTHDAY"] = .array(byMonthDay.map { .int(Int64($0)) })
    }
    if let bySetPos = recurrence.bySetPos {
      object["BYSETPOS"] = .array(bySetPos.map { .int(Int64($0)) })
    }
    if let wkst = recurrence.wkst { object["WKST"] = .string(wkst) }
    if let until = recurrence.until { object["UNTIL"] = .string(until) }
    if let count = recurrence.count { object["COUNT"] = .int(Int64(count)) }
    if let anchor = recurrence.anchor { object["ANCHOR"] = .string(anchor) }
    let raw: String
    do {
      raw = try canonicalizeJSON(.object(object))
    } catch {
      throw Mismatch(detail: "task \(taskID) has an unserializable portable recurrence")
    }
    return try normalizedRecurrence(raw, taskID: taskID, source: "portable")
  }

  private static func normalizedNativeRecurrence(
    _ recurrence: String?, taskID: String
  ) throws -> String? {
    guard let recurrence else { return nil }
    return try normalizedRecurrence(recurrence, taskID: taskID, source: "native")
  }

  private static func normalizedRecurrence(
    _ raw: String, taskID: String, source: String
  ) throws -> String {
    do {
      return try BackupV1RecurrenceSemantics.canonicalize(raw)
    } catch {
      throw Mismatch(detail: "task \(taskID) has invalid \(source) recurrence: \(error)")
    }
  }

  private static func requireUnique(
    _ values: [String], label: String, taskID: String
  ) throws {
    guard Set(values).count == values.count else {
      throw Mismatch(detail: "task \(taskID) repeats a \(label)")
    }
  }
}

extension LorvexDataImporter {
  static func validateBackupV1TaskProjection(_ payload: LorvexDataExportPayload) throws {
    guard let nativeGraph = payload.nativeTaskGraph else { return }
    do {
      try BackupV1TaskProjectionConsistency.validate(
        portableTasks: payload.tasks ?? [], nativeGraph: nativeGraph,
        portableTags: payload.tags)
    } catch {
      throw ImportError.inconsistentTaskRepresentations(error.localizedDescription)
    }
  }
}
