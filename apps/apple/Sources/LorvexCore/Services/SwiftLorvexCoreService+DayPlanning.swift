import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// `LorvexDayPlanningServicing` over the pure-Swift core: the times of a day's
/// tasks.
///
/// A time is part of its task (`tasks.planned_start_minutes` and
/// `tasks.planned_end_minutes`), so reading a day's times reads tasks, and
/// saving them is one batch task update whose task envelopes carry the times to
/// other devices. A save also writes one `daily_schedule` changelog row whose
/// before and after states hold the date and time of every task it changed
/// (``dayTimesState(_:ids:date:)``), so the log shows what the save replaced.
/// Suggestions come from `DayScheduleProposal`, the packer the assistant's
/// `propose_daily_schedule` reads too.
extension SwiftLorvexCoreService {
  public func loadTimedTasks(from start: String, through end: String) async throws
    -> [LorvexTask]
  {
    try read { db in try Self.timedTasks(db, from: start, through: end) }
  }

  public func proposeDayTimes(date: String) async throws -> DayTimesProposal {
    try await proposeDayTimes(
      date: date, workingHoursStart: nil, workingHoursEnd: nil, includeCalendarEvents: nil)
  }

  public func proposeDayTimes(
    date: String,
    workingHoursStart: String?,
    workingHoursEnd: String?,
    includeCalendarEvents: Bool?
  ) async throws -> DayTimesProposal {
    let day = try Self.canonicalDay(date)
    let now = wallClock()
    return try read { db in
      let anchorTimezone =
        try WorkflowTimezone.activeTimezoneName(db) ?? TimeZone.current.identifier
      // The stored calendar access tier bounds what a suggestion says about
      // device calendar events, in the app and to the assistant alike. A
      // malformed tier fails the read instead of sharing more than it allows.
      let accessMode = try DeviceStateRepo.readCalendarAiAccessMode(db)
      let proposal = try DayScheduleProposal.propose(
        db, date: day, anchorTimezone: anchorTimezone, accessMode: accessMode,
        workingHoursStart: workingHoursStart, workingHoursEnd: workingHoursEnd,
        includeCalendarEvents: includeCalendarEvents ?? true,
        notBefore: Self.proposalStartFloor(date: day, timezoneName: anchorTimezone, now: now))
      return try Self.dayTimesProposal(
        db, proposal, sharesEventDetails: accessMode.includesDetails)
    }
  }

  public func saveDayTimes(date: String, times: [LorvexTaskTime]) async throws -> [LorvexTask] {
    try saveDayTimesWithReceipt(date: date, times: times).timedTasks
  }

  public func saveDayTimesForMcp(date: String, times: [LorvexTaskTime]) async throws
    -> McpDayTimesSaveReceipt
  {
    try saveDayTimesWithReceipt(date: date, times: times)
  }

  private func saveDayTimesWithReceipt(date: String, times: [LorvexTaskTime]) throws
    -> McpDayTimesSaveReceipt
  {
    let day = try Self.canonicalDay(date)
    var listed = Set<String>()
    for entry in times {
      guard listed.insert(entry.taskID).inserted else {
        throw LorvexCoreError.validation(
          field: "times", message: "Task \(entry.taskID) appears more than once.")
      }
      guard entry.time.lowerBound >= 0, entry.time.upperBound <= 1440, !entry.time.isEmpty
      else {
        throw LorvexCoreError.validation(
          field: "times",
          message: "The time of task \(entry.taskID) must be a start before an end within the day.")
      }
    }
    return try withWrite { db, hlc, deviceId in
      let listedIDs = times.map(\.taskID)
      let unfinished = try Self.unfinishedTaskIDs(db, among: listedIDs)
      if let finished = listedIDs.first(where: { !unfinished.contains($0) }) {
        throw LorvexCoreError.validation(
          field: "times",
          message: "Task \(finished) is not an open or started task, so it cannot take a time.")
      }
      let displaced = try String.fetchAll(
        db,
        sql: """
          SELECT id FROM tasks
          WHERE planned_date = ?
            AND planned_start_minutes IS NOT NULL
            AND archived_at IS NULL
            AND status IN (\(StatusName.actionableStatusSqlList))
          ORDER BY planned_start_minutes, id
          """,
        arguments: [day]
      ).filter { !listed.contains($0) }

      let before = try Self.plannedStates(db, ids: listedIDs + displaced)
      var updates: [TaskUpdateInput] = []
      for entry in times
      where before[entry.taskID] != PlannedState(date: day, time: entry.time) {
        updates.append(
          TaskUpdateInput(
            id: entry.taskID, plannedDate: .set(day),
            plannedStartTime: .set(TimeOfDay.rangeBoundString(entry.time.lowerBound)),
            plannedEndTime: .set(TimeOfDay.rangeBoundString(entry.time.upperBound))))
      }
      for id in displaced {
        updates.append(TaskUpdateInput(id: id, plannedStartTime: .clear, plannedEndTime: .clear))
      }

      if !updates.isEmpty {
        let changedIDs = updates.map(\.id)
        var beforeSyncPayloads: [String: JSONValue] = [:]
        for id in changedIDs {
          beforeSyncPayloads[id] = try OutboxEnqueue.readEntityPayloadSnapshot(
            db, entityType: EntityName.task, entityId: id)
        }
        let result = try TaskBatchUpdate.batchUpdateTasksInTransaction(
          db, hlc: hlc, input: BatchUpdateTasksInput(updates: updates))
        var registerIntents: [String: TaskRegisterIntent] = [:]
        for (id, beforePayload) in beforeSyncPayloads {
          let afterPayload = try OutboxEnqueue.readEntityPayloadSnapshot(
            db, entityType: EntityName.task, entityId: id)
          registerIntents[id] = try TaskRegisterIntent.authoredRegisters(
            between: beforePayload, and: afterPayload)
        }
        try self.flushTaskUpdateEffects(
          db, hlc: hlc, deviceId: deviceId, effects: result.syncEffects,
          primaryRegisterIntents: registerIntents)
        let after = try Self.plannedStates(db, ids: changedIDs)
        try self.writeChangelogRow(
          db,
          ChangelogEntry(
            // Clearing every time reads as removing the day's schedule; either
            // row records both states, so either can be undone.
            operation: times.isEmpty ? SyncNaming.opDelete : SyncNaming.opUpsert,
            entityType: EntityName.dailySchedule,
            entityId: day, entityIds: changedIDs,
            summary: times.isEmpty ? "Cleared the times for \(day)" : "Saved times for \(day)",
            before: Self.dayTimesState(before, ids: changedIDs, date: day),
            after: Self.dayTimesState(after, ids: changedIDs, date: day)),
          deviceId: deviceId)
      }

      let cleared = try TaskResponse.loadEnrichedTasksJSON(db, taskIds: displaced)
        .map(SwiftLorvexTaskDeserializers.task)
      return McpDayTimesSaveReceipt(
        date: day, timedTasks: try Self.timedTasks(db, from: day, through: day),
        clearedTasks: cleared)
    }
  }

  // MARK: - Reads

  /// Every task with a time on a day from `start` through `end`, finished ones
  /// included and cancelled, parked, or trashed ones left out, ordered by day,
  /// then start.
  static func timedTasks(_ db: Database, from start: String, through end: String) throws
    -> [LorvexTask]
  {
    let ids = try String.fetchAll(
      db,
      sql: """
        SELECT id FROM tasks
        WHERE planned_start_minutes IS NOT NULL
          AND planned_date >= ? AND planned_date <= ?
          AND archived_at IS NULL
          AND status IN (?, ?, ?)
        ORDER BY planned_date, planned_start_minutes, planned_end_minutes, id
        """,
      arguments: [start, end, StatusName.open, StatusName.inProgress, StatusName.completed])
    return try TaskResponse.loadEnrichedTasksJSON(db, taskIds: ids)
      .map(SwiftLorvexTaskDeserializers.task)
  }

  /// The ids among `ids` of tasks that exist, are not in the Trash, and are
  /// open or started.
  private static func unfinishedTaskIDs(_ db: Database, among ids: [String]) throws -> Set<String> {
    guard !ids.isEmpty else { return [] }
    let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
    return Set(
      try String.fetchAll(
        db,
        sql: """
          SELECT id FROM tasks
          WHERE id IN (\(placeholders))
            AND archived_at IS NULL
            AND status IN (\(StatusName.actionableStatusSqlList))
          """,
        arguments: StatementArguments(ids)))
  }

  // MARK: - Changelog state

  /// A task's planned date and time, as a save compares and records them.
  struct PlannedState: Equatable {
    var date: String?
    var time: Range<Int>?
  }

  private static func plannedStates(_ db: Database, ids: [String]) throws
    -> [String: PlannedState]
  {
    guard !ids.isEmpty else { return [:] }
    let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT id, planned_date, planned_start_minutes, planned_end_minutes
        FROM tasks WHERE id IN (\(placeholders))
        """,
      arguments: StatementArguments(ids))
    var states: [String: PlannedState] = [:]
    for row in rows {
      let start: Int? = row["planned_start_minutes"]
      let end: Int? = row["planned_end_minutes"]
      var time: Range<Int>?
      if let start, let end, start < end { time = start..<end }
      states[row["id"]] = PlannedState(date: row["planned_date"], time: time)
    }
    return states
  }

  /// The before or after state of a `daily_schedule` changelog row:
  /// `{"date": …, "tasks": [{"id", "planned_date", "planned_start_minutes",
  /// "planned_end_minutes"}]}` for each of `ids`, in order, with JSON null for
  /// an absent date or time.
  static func dayTimesState(_ states: [String: PlannedState], ids: [String], date: String)
    -> JSONValue
  {
    .object([
      "date": .string(date),
      "tasks": .array(
        ids.map { id in
          let state = states[id]
          return .object([
            "id": .string(id),
            "planned_date": state?.date.map(JSONValue.string) ?? .null,
            "planned_start_minutes": state?.time.map { .int(Int64($0.lowerBound)) } ?? .null,
            "planned_end_minutes": state?.time.map { .int(Int64($0.upperBound)) } ?? .null,
          ])
        }),
    ])
  }

  // MARK: - Proposal mapping

  static func dayTimesProposal(
    _ db: Database, _ proposal: DayScheduleProposal.Proposal, sharesEventDetails: Bool
  ) throws -> DayTimesProposal {
    let ids = proposal.slots.map(\.task.id) + proposal.unscheduled.map(\.id)
    let tasks = try TaskResponse.loadEnrichedTasksJSON(db, taskIds: ids)
      .map(SwiftLorvexTaskDeserializers.task)
    let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let workingStart = proposal.workingHours.start.minutesOfDay
    let workingEnd = max(proposal.workingHours.end.minutesOfDay, workingStart)
    return DayTimesProposal(
      date: proposal.date.asString,
      workingHours: workingStart..<workingEnd,
      availableMinutes: Int(proposal.totalMinutesAvailable),
      placements: proposal.slots.compactMap { slot in
        guard let task = byID[slot.task.id], slot.end > slot.start else { return nil }
        return DayTimesProposal.Placement(task: task, time: Int(slot.start)..<Int(slot.end))
      },
      events: proposal.events.compactMap { event in
        guard event.end > event.start else { return nil }
        let source: DayTimesProposal.Event.Source =
          event.source == .canonical ? .canonical : .provider
        return DayTimesProposal.Event(
          time: Int(event.start)..<Int(event.end),
          title: source == .provider && !sharesEventDetails ? nil : event.title,
          eventID: event.calendarEventId,
          source: source)
      },
      unscheduled: proposal.unscheduled.compactMap { byID[$0.id] })
  }

  // MARK: - Dates and times

  /// `date` as a canonical `YYYY-MM-DD` key; a malformed date is a validation
  /// error on `date`.
  static func canonicalDay(_ date: String) throws -> String {
    guard
      case .success(let parsed) = IsoDate.parseIsoDate(
        date.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      throw LorvexCoreError.validation(
        field: "date", message: "date must be a valid YYYY-MM-DD date.")
    }
    return parsed.canonicalString
  }

  /// The earliest time a suggestion for `date` may place work. On today's date
  /// in `timezoneName` it is the current time rounded up to the next five
  /// minutes, so the suggestion starts from now instead of from a morning that
  /// has already passed. Any other date has no floor and packs from its
  /// working-hours start.
  static func proposalStartFloor(date: String, timezoneName: String, now: Date) -> TimeOfDay? {
    guard
      Timezone.todayYmdForTimezoneName(
        now: now, timezoneName: timezoneName, systemFallback: TimeZone.current) == date
    else { return nil }
    let minutes = localTimeOfDay(now: now, timezoneName: timezoneName).minutesOfDay
    return TimeOfDay.fromMinutesSaturating((minutes + 4) / 5 * 5)
  }
}
