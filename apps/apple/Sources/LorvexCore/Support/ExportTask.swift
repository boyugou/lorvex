import Foundation

/// One checklist row inside a task export, in display order.
public struct ExportChecklistItem: Codable, Sendable {
  public var id: String?
  public var position: Int?
  public var text: String
  public var completed: Bool
  public var completedAt: String?
  public var createdAt: String?
  public var updatedAt: String?

  public init(
    id: String? = nil,
    position: Int? = nil,
    text: String,
    completed: Bool,
    completedAt: String? = nil,
    createdAt: String? = nil,
    updatedAt: String? = nil
  ) {
    self.id = id
    self.position = position
    self.text = text
    self.completed = completed
    self.completedAt = completedAt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public init(from item: TaskChecklistItem) {
    id = item.id
    position = item.position
    text = item.text
    completed = item.completedAt != nil
    completedAt = item.completedAt
    createdAt = item.createdAt
    updatedAt = item.updatedAt
  }
}

public struct ExportTaskReminder: Codable, Sendable {
  public var id: String
  public var reminderAt: String
  public var dismissedAt: String?
  public var cancelledAt: String?
  public var createdAt: String?
  public var originalLocalTime: String?
  public var originalTz: String?

  public init(
    id: String,
    reminderAt: String,
    dismissedAt: String? = nil,
    cancelledAt: String? = nil,
    createdAt: String? = nil,
    originalLocalTime: String? = nil,
    originalTz: String? = nil
  ) {
    self.id = id
    self.reminderAt = reminderAt
    self.dismissedAt = dismissedAt
    self.cancelledAt = cancelledAt
    self.createdAt = createdAt
    self.originalLocalTime = originalLocalTime
    self.originalTz = originalTz
  }

  public init(from reminder: TaskReminder) {
    id = reminder.id
    reminderAt = reminder.reminderAt
    dismissedAt = reminder.dismissedAt
    cancelledAt = reminder.cancelledAt
    createdAt = reminder.createdAt
    originalLocalTime = reminder.originalLocalTime
    originalTz = reminder.originalTz
  }
}

/// A task's recurrence rule in an export, mirroring `TaskRecurrenceRule`
/// field-for-field (`freq` as its raw string).
public struct ExportRecurrenceRule: Codable, Sendable {
  public var freq: String
  public var interval: Int?
  public var byDay: [String]?
  public var byMonth: [Int]?
  public var byMonthDay: [Int]?
  public var bySetPos: [Int]?
  public var wkst: String?
  public var until: String?
  public var count: Int?
  /// The recurrence anchor (`schedule` fixed-cadence vs `completion`-relative).
  /// Omitted for the default `schedule` so a fixed-cadence rule stays compact;
  /// carried verbatim for `completion` so a completion-anchored task survives a
  /// round-trip instead of silently reverting to `schedule`.
  public var anchor: String?

  public init(from rule: TaskRecurrenceRule) {
    freq = rule.freq.rawValue
    interval = rule.interval
    byDay = rule.byDay
    byMonth = rule.byMonth
    byMonthDay = rule.byMonthDay
    bySetPos = rule.bySetPos
    wkst = rule.wkst
    until = rule.until
    count = rule.count
    anchor = rule.anchor == .completion ? rule.anchor.rawValue : nil
  }

  /// `nil` when `freq` is not a known frequency raw value.
  public var rule: TaskRecurrenceRule? {
    guard let frequency = TaskRecurrenceRule.Frequency(rawValue: freq),
      let parsedAnchor = TaskRecurrenceRule.Anchor(rawValue: anchor ?? "schedule")
    else { return nil }
    return TaskRecurrenceRule(
      freq: frequency, interval: interval, byDay: byDay, byMonth: byMonth,
      byMonthDay: byMonthDay, bySetPos: bySetPos, wkst: wkst, until: until, count: count,
      anchor: parsedAnchor)
  }
}

/// Flat DTO for a task row in an export.
/// A task in the portable export/import format: a *semantic* snapshot, not a
/// byte-mirror of the `tasks` row. Cross-platform data movement is AI-reconciled
/// best-effort (see the monorepo `CLAUDE.md`), so a few columns are deliberately
/// NON-PORTABLE and reconstructed on import rather than carried:
///
/// - **Recurrence lineage** (`spawned_from`, `recurrence_group_id`,
///   `recurrence_instance_key`, `canonical_occurrence_date`) — series identity is
///   re-derived from ``recurrence`` on import, so exporting the stored lineage
///   would be redundant and could contradict the re-derivation.
///
/// Everything a user would notice — title, body, priority, status, dates,
/// tags, dependencies, checklist, reminders, the recurrence rule and its
/// exceptions, defer history, and lifecycle timestamps — is carried.
public struct ExportTask: Codable, Sendable {
  public var id: String
  public var title: String
  /// Task body. Omitted from the export when empty.
  public var notes: String?
  public var priority: String
  public var status: String
  public var dueDate: String?
  public var plannedDate: String?
  public var availableFrom: String?
  public var estimatedMinutes: Int?
  /// Tag display names as a first-class array. Omitted when the task has no tags.
  public var tags: [String]?
  public var rawInput: String?
  /// Blocker task ids as a first-class array. Omitted when the task blocks on
  /// nothing.
  public var dependsOn: [String]?
  public var listID: String?
  public var aiNotes: String?
  /// Checklist rows in display order. Optional in the wire format so older
  /// archives still decode.
  public var checklist: [ExportChecklistItem]?
  /// Full reminder rows in creation order. `nil` when the task has no reminders.
  public var reminders: [ExportTaskReminder]?
  public var recurrence: ExportRecurrenceRule?
  /// Skipped-occurrence dates (`YYYY-MM-DD`) as a first-class array. Omitted when
  /// the task has no exceptions.
  public var recurrenceExceptions: [String]?
  public var deferCount: Int?
  public var lastDeferReason: String?
  public var lastDeferredAt: String?
  public var completedAt: String?
  public var createdAt: String?
  public var updatedAt: String?
  public var archivedAt: String?

  public init(
    id: String,
    title: String,
    notes: String? = nil,
    priority: String,
    status: String,
    dueDate: String?,
    plannedDate: String? = nil,
    availableFrom: String? = nil,
    estimatedMinutes: Int?,
    tags: [String]? = nil,
    rawInput: String? = nil,
    dependsOn: [String]? = nil,
    listID: String? = nil,
    aiNotes: String? = nil,
    checklist: [ExportChecklistItem]? = nil,
    reminders: [ExportTaskReminder]? = nil,
    recurrence: ExportRecurrenceRule? = nil,
    recurrenceExceptions: [String]? = nil,
    deferCount: Int? = nil,
    lastDeferReason: String? = nil,
    lastDeferredAt: String? = nil,
    completedAt: String? = nil,
    createdAt: String? = nil,
    updatedAt: String? = nil,
    archivedAt: String? = nil
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.priority = priority
    self.status = status
    self.dueDate = dueDate
    self.plannedDate = plannedDate
    self.availableFrom = availableFrom
    self.estimatedMinutes = estimatedMinutes
    self.tags = tags
    self.rawInput = rawInput
    self.dependsOn = dependsOn
    self.listID = listID
    self.aiNotes = aiNotes
    self.checklist = checklist
    self.reminders = reminders
    self.recurrence = recurrence
    self.recurrenceExceptions = recurrenceExceptions
    self.deferCount = deferCount
    self.lastDeferReason = lastDeferReason
    self.lastDeferredAt = lastDeferredAt
    self.completedAt = completedAt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.archivedAt = archivedAt
  }

  public init(from task: LorvexTask) {
    id = task.id
    title = task.title
    notes = task.notes.isEmpty ? nil : task.notes
    priority = task.priority.rawValue
    status = task.status.rawValue
    // All timestamps carry the fractional-millisecond `Z` precision the core
    // stores, so due/planned/availableFrom match every other exported timestamp.
    dueDate = task.dueDate.map { LorvexDateFormatters.iso8601Fractional.string(from: $0) }
    plannedDate = task.plannedDate.map { LorvexDateFormatters.iso8601Fractional.string(from: $0) }
    availableFrom = task.availableFrom.map { LorvexDateFormatters.iso8601Fractional.string(from: $0) }
    estimatedMinutes = task.estimatedMinutes
    tags = task.tags.isEmpty ? nil : task.tags
    rawInput = task.rawInput
    dependsOn = task.dependsOn.isEmpty ? nil : task.dependsOn
    listID = task.listID
    aiNotes = task.aiNotes
    checklist = task.checklistItems.isEmpty
      ? nil
      : task.checklistItems
        .sorted { $0.position < $1.position }
        .map(ExportChecklistItem.init(from:))
    reminders = task.reminders.isEmpty ? nil : task.reminders.map(ExportTaskReminder.init(from:))
    recurrence = task.recurrence.map(ExportRecurrenceRule.init(from:))
    recurrenceExceptions = task.recurrenceExceptions.isEmpty ? nil : task.recurrenceExceptions
    deferCount = task.deferCount
    lastDeferReason = task.lastDeferReason
    lastDeferredAt = task.lastDeferredAt
    completedAt = task.completedAt
    createdAt = task.createdAt
    updatedAt = task.updatedAt
    archivedAt = task.archivedAt
  }

  static let columns = [
    "id", "title", "notes", "priority", "status", "dueDate", "estimatedMinutes", "tags",
    "plannedDate", "availableFrom", "rawInput", "dependsOn", "listID", "aiNotes", "checklist",
    "reminders", "recurrence", "recurrenceExceptions", "deferCount", "lastDeferReason",
    "lastDeferredAt", "completedAt", "createdAt", "updatedAt", "archivedAt",
  ]

  var csvRow: [String] {
    [
      id, title, notes ?? "", priority, status, dueDate ?? "",
      estimatedMinutes.map(String.init) ?? "", (tags ?? []).joined(separator: "|"),
      plannedDate ?? "", availableFrom ?? "",
      rawInput ?? "", (dependsOn ?? []).joined(separator: "|"), listID ?? "", aiNotes ?? "",
      checklist.map { items in
        items.map { ($0.completed ? "[x] " : "[ ] ") + $0.text }.joined(separator: "|")
      } ?? "",
      reminders.map { rows in
        rows.map(\.reminderAt).joined(separator: "|")
      } ?? "",
      recurrence.map { rule in
        ([("FREQ", rule.freq)]
          + [("INTERVAL", rule.interval.map(String.init))].compactMap { name, v in
            v.map { (name, $0) }
          })
          .map { "\($0.0)=\($0.1)" }.joined(separator: ";")
      } ?? "",
      (recurrenceExceptions ?? []).joined(separator: "|"),
      deferCount.map(String.init) ?? "",
      lastDeferReason ?? "", lastDeferredAt ?? "", completedAt ?? "", createdAt ?? "",
      updatedAt ?? "", archivedAt ?? "",
    ]
  }
}
