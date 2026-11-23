import Foundation
import LorvexDomain
import LorvexWorkflow

/// What a Siri reminder request gives for a task, in the system's types. A nil
/// field, or an empty `urls`, is one the request did not give.
public struct SiriTaskFields: Equatable, Sendable {
  public var title: String?
  public var note: String?
  public var tags: Set<String>?
  public var urls: [URL]
  /// The reminder's one date; see ``SiriTaskMapping`` for what it sets.
  public var date: DateComponents?
  public var recurrence: Calendar.RecurrenceRule?
  public var isCompleted: Bool?
  /// A flagged reminder is a P1 task.
  public var isFlagged: Bool?
  public var listID: LorvexList.ID?

  public init(
    title: String? = nil,
    note: String? = nil,
    tags: Set<String>? = nil,
    urls: [URL] = [],
    date: DateComponents? = nil,
    recurrence: Calendar.RecurrenceRule? = nil,
    isCompleted: Bool? = nil,
    isFlagged: Bool? = nil,
    listID: LorvexList.ID? = nil
  ) {
    self.title = title
    self.note = note
    self.tags = tags
    self.urls = urls
    self.date = date
    self.recurrence = recurrence
    self.isCompleted = isCompleted
    self.isFlagged = isFlagged
    self.listID = listID
  }
}

extension LorvexSystemIntentRunner {
  /// Create the task a Siri reminder request describes.
  ///
  /// The date becomes the planned day, with a planned time of
  /// ``SiriTaskMapping/defaultTimeLength`` minutes when it names a clock time.
  /// A flag makes the task P1. Links are added to the notes. A task that
  /// repeats gets its due day on the first day the rule lands on, counted from
  /// the given date or from the logical today. Every field is read before the
  /// write, so a date or a repeat rule a task cannot hold fails without
  /// creating anything.
  public static func createSiriTask(
    _ fields: SiriTaskFields,
    now: Date = Date(),
    timeZone: TimeZone = .current,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    let title = (fields.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { throw LorvexCoreError.emptyTitle }
    let moment = try fields.date.map {
      try SiriTaskMapping.moment(from: $0, now: now, timeZone: timeZone)
    }
    let rule = try fields.recurrence.map {
      try SiriTaskMapping.taskRecurrence(from: $0, timeZone: timeZone)
    }

    var draft = TaskCreateDraft(title: title)
    draft.notes = SiriTaskMapping.notes(fields.note ?? "", appending: fields.urls)
    draft.listID = fields.listID
    if fields.isFlagged == true { draft.priority = .p1 }
    if let tags = fields.tags, !tags.isEmpty { draft.tags = tags.sorted() }
    draft.plannedDate = moment?.day
    draft.plannedTime = moment?.startMinutes.map {
      SiriTaskMapping.plannedTime(startingAt: $0, replacing: nil, estimatedMinutes: nil)
    }
    if let rule, let systemRule = fields.recurrence {
      draft.recurrence = rule
      let start = try await siriLogicalToday(orDay: moment?.day, core: core)
      draft.dueDate = SiriTaskMapping.firstOccurrenceDay(of: systemRule, onOrAfter: start)
    }
    return try await core.createTask(draft)
  }

  /// Apply the fields a Siri reminder request gives to a task and leave every
  /// other field as stored.
  ///
  /// A field given with the value the task already reports is not written.
  /// That matters for the two fields this shape cannot report exactly: a task
  /// with only a deadline reports the deadline as its date, and a task that
  /// repeats from its completion day reports a plain repeat. Restating either
  /// must not add a planned day or change what the repeat counts from.
  ///
  /// A date sets the planned day, and the planned time when it names a clock
  /// time; a day without a time on another day clears the time, as every
  /// planned-day move does. A flag makes the task P1, and removing the flag
  /// makes a P1 task P2 and leaves other priorities alone. A repeat rule
  /// replaces the task's rule, and a task without a due day gets one on the
  /// first day the rule lands on. The rule moves the due day from one
  /// occurrence to the next, and the planned day keeps its distance from the
  /// due day. Completing or reopening runs last.
  ///
  /// Every field is read before the first write, so a date or a repeat rule a
  /// task cannot hold fails without changing the task. The fields, the repeat
  /// rule and the completion are three writes: when a later one is refused,
  /// for example because another device changed the task in between, the
  /// earlier ones stay saved and the request fails.
  public static func updateSiriTask(
    id: LorvexTask.ID,
    fields: SiriTaskFields,
    now: Date = Date(),
    timeZone: TimeZone = .current,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTask {
    let taskID = try validatedTaskID(id)
    let current = try await core.loadTask(id: taskID)
    var draft = TaskUpdateDraft(id: taskID)

    if let title = fields.title?.trimmingCharacters(in: .whitespacesAndNewlines) {
      guard !title.isEmpty else { throw LorvexCoreError.emptyTitle }
      if title != current.title { draft.title = title }
    }
    if fields.note != nil || !fields.urls.isEmpty {
      let notes = SiriTaskMapping.notes(fields.note ?? current.notes, appending: fields.urls)
      if notes != current.notes { draft.notes = notes }
    }
    if let tags = fields.tags, tags != Set(current.tags) { draft.tags = tags.sorted() }
    if fields.isFlagged == true, current.priority != .p1 { draft.priority = .p1 }
    if fields.isFlagged == false, current.priority == .p1 { draft.priority = .p2 }
    if let listID = fields.listID, listID != current.listID ?? LorvexListNaming.inboxID {
      draft.listID = listID
    }

    var movedDay: Date?
    if let components = fields.date {
      let moment = try SiriTaskMapping.moment(from: components, now: now, timeZone: timeZone)
      if moment != SiriTaskMapping.moment(for: current) {
        if moment.day != current.plannedDate {
          draft.plannedDate = .set(moment.day)
          movedDay = moment.day
        }
        if let start = moment.startMinutes {
          let time = SiriTaskMapping.plannedTime(
            startingAt: start, replacing: current.plannedTime,
            estimatedMinutes: current.estimatedMinutes)
          if movedDay != nil || time != current.plannedTime { draft.plannedTime = .set(time) }
        }
      }
    }

    var newRule: TaskRecurrenceRule?
    if let systemRule = fields.recurrence {
      let rule = try SiriTaskMapping.taskRecurrence(from: systemRule, timeZone: timeZone)
      let restated = current.recurrence.map { SiriTaskMapping.repeatsOnSameDays($0, rule) }
      if restated != true {
        newRule = rule
        if current.dueDate == nil {
          let start = try await siriLogicalToday(
            orDay: movedDay ?? current.plannedDate, core: core)
          draft.dueDate = .set(
            SiriTaskMapping.firstOccurrenceDay(of: systemRule, onOrAfter: start))
        }
      }
    }

    var task = current
    if draft != TaskUpdateDraft(id: taskID) { task = try await core.updateTask(draft) }
    if let newRule { task = try await core.setTaskRecurrence(taskID: taskID, rule: newRule) }
    if fields.isCompleted == true, current.status != .completed {
      task = try await core.completeTaskReturningTask(id: taskID)
    }
    if fields.isCompleted == false, current.status == .completed {
      task = try await core.reopenTaskReturningTask(id: taskID)
    }
    return task
  }

  /// Cancel the tasks a Siri delete request names.
  ///
  /// A delete through Siri cancels: the tasks stay in the store, where they
  /// can be reopened, since one request from an assistant never destroys a
  /// task. A repeating task stops repeating, so the deleted task does not come
  /// back as its next occurrence.
  ///
  /// A task that is already cancelled or gone needs nothing and is reported
  /// as skipped. A task that cannot be cancelled fails the request with its
  /// reason after the others are cancelled: a completed task, which stays
  /// completed, and an occurrence of a repeating task with a later occurrence
  /// that is already completed, which ending the series would cancel.
  public static func cancelSiriTasks(
    ids: [LorvexTask.ID],
    core: any LorvexCoreServicing
  ) async throws -> TaskBatchCancelByIdResult {
    let taskIDs = try ids.map(validatedTaskID)
    guard !taskIDs.isEmpty else {
      throw LorvexCoreError.validation(
        field: "task_ids", message: "At least one task ID is required.")
    }
    let result = try await core.batchCancelTasks(ids: taskIDs, cancelSeries: true)
    for id in result.skipped {
      let task: LorvexTask
      do {
        task = try await core.loadTask(id: id)
      } catch LorvexCoreError.taskNotFound {
        continue
      }
      switch task.status {
      case .cancelled:
        continue
      case .completed:
        throw TaskLifecycleError.finishedTaskTransition(
          taskId: id, from: .completed, to: .cancelled)
      default:
        // A batch that ends each series leaves an active task alone for one
        // reason, and does not say which occurrence stood in the way.
        throw TaskLifecycleError.seriesEndBlockedByCompletedOccurrence(
          taskId: id, successorId: "")
      }
    }
    return result
  }

  /// `day` when there is one, else the stored day of the logical today.
  private static func siriLogicalToday(
    orDay day: Date?, core: any LorvexCoreServicing
  ) async throws -> Date {
    if let day { return day }
    let today = try await core.getSessionContext().date
    return try storageDate(byAddingDays: 0, toLogicalDay: today)
  }
}
