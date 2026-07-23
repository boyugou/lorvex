import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexWorkflow

/// `LorvexTaskServicing` query methods over the
/// pure-Swift core's `TaskRepo` read paths. Results are mapped onto the app's
/// stable model types via `SwiftLorvexTaskDeserializers`, with the
/// `returned` / `nextOffset` / `truncated` pagination metadata derived alongside.
extension SwiftLorvexCoreService {

  public func taskIntakeAdvice(id: LorvexTask.ID) async throws -> [TaskIntakeAdviceItem] {
    try read { db in
      let taskJSON: JSONValue
      do {
        taskJSON = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: id))
      } catch {
        return []  // unknown id → no advice rather than an error
      }
      return try TaskCreateAdvice.buildTaskIntakeAdvice(db, task: taskJSON)
        .compactMap(Self.taskIntakeAdviceItem(from:))
    }
  }

  static func taskIntakeAdviceItem(from json: JSONValue) -> TaskIntakeAdviceItem? {
    guard case let .object(fields) = json,
      case let .string(code) = fields["code"] ?? .null,
      case let .string(severity) = fields["severity"] ?? .null,
      case let .string(message) = fields["message"] ?? .null
    else { return nil }
    var relatedIDs: [String] = []
    if case let .array(related) = fields["related_tasks"] ?? .null {
      for entry in related {
        if case let .object(row) = entry, case let .string(rid) = row["id"] ?? .null {
          relatedIDs.append(rid)
        }
      }
    }
    return TaskIntakeAdviceItem(
      code: code, severity: severity, message: message, relatedTaskIDs: relatedIDs)
  }

  public func getUpcomingTasks(daysAhead: Int, limit: Int) async throws -> [LorvexTask] {
    try await getUpcomingTaskPage(daysAhead: daysAhead, limit: limit, offset: 0).tasks
  }

  public func getUpcomingTaskPage(daysAhead: Int, limit: Int, offset: Int) async throws
    -> TaskPageResult
  {
    return try read { db in
      let todayString = try WorkflowTimezone.todayYmdForConn(db)
      let today: IsoDate.YMD
      switch IsoDate.parseIsoDate(todayString) {
      case .success(let ymd): today = ymd
      case .failure(let error): throw StoreError.invariant(error.description)
      }
      let predicate = UpcomingPredicate(fromDate: today, days: UInt32(clamping: max(1, daysAhead)))
      let clampedLimit = min(max(1, limit), 500)
      // Upper-bound the offset so the UInt32 narrowing below can never trap on a
      // hostile/huge `offset` from an MCP client (saturates instead of crashing).
      let clampedOffset = min(max(0, offset), Int(UInt32.max))
      let page = Pagination(limit: UInt32(clampedLimit), offset: UInt32(clampedOffset))
      let rows = try TaskRepo.Read.getUpcomingTasks(db, predicate: predicate, page: page)
      let total = try TaskRepo.Read.countUpcomingTasks(db, predicate: predicate)
      let tasks = try Self.enrich(db, rows: rows)
      return Self.pageResult(
        tasks: tasks,
        totalMatching: Int(total),
        limit: clampedLimit,
        offset: clampedOffset
      )
    }
  }

  public func getTodayTasks(limit: Int, offset: Int) async throws -> TaskPageResult {
    try read { db in
      let todayString = try WorkflowTimezone.todayYmdForConn(db)
      return try Self.getTodayTaskPage(
        db, date: todayString, limit: limit, offset: offset)
    }
  }

  public func getTodayTasks(date: String, limit: Int, offset: Int) async throws
    -> TaskPageResult
  {
    try read { db in
      try Self.getTodayTaskPage(db, date: date, limit: limit, offset: offset)
    }
  }

  private static func getTodayTaskPage(
    _ db: Database, date: String, limit: Int, offset: Int
  ) throws -> TaskPageResult {
    let today: IsoDate.YMD
    switch IsoDate.parseIsoDate(date) {
    case .success(let ymd): today = ymd
    case .failure(let error): throw StoreError.validation(error.description)
    }
    let clampedLimit = min(max(1, limit), 500)
    // Upper-bound the offset so the UInt32 narrowing below can never trap on a
    // hostile/huge `offset` from an MCP client (saturates instead of crashing).
    let clampedOffset = min(max(0, offset), Int(UInt32.max))
    let predicate = TodayPredicate(date: today)
    let page = Pagination(limit: UInt32(clampedLimit), offset: UInt32(clampedOffset))
    let rows = try TaskRepo.Read.getTodayTasks(db, predicate: predicate, page: page)
    let total = try TaskRepo.Read.countTodayTasks(db, predicate: predicate)
    let tasks = try Self.enrich(db, rows: rows)
    return Self.pageResult(
      tasks: tasks,
      totalMatching: Int(total),
      limit: clampedLimit,
      offset: clampedOffset
    )
  }

  public func getScheduledTasks(from: String, to: String, limit: Int) async throws -> [LorvexTask] {
    try read { db in
      let clampedLimit = min(max(1, limit), 500)
      // The calendar lane's day is planned-first with a deadline fallback —
      // `planned_date ?? due_date`, mirroring the reference product's
      // calendar controller. Filtering due_date alone hid every app-planned
      // task from the week view (app writes set planned_date only).
      let query = TaskRepo.ListTasksQuery(
        status: .all,
        scheduledRange: .init(from: from, to: to),
        limit: UInt32(clampedLimit),
        offset: 0)
      let result = try TaskRepo.Read.listTasks(db, query: query)
      return try Self.enrich(db, rows: result.rows)
    }
  }

  public func getHiddenScheduledTasks(limit: Int, offset: Int) async throws -> TaskPageResult {
    try read { db in
      let today = try WorkflowTimezone.todayYmdForConn(db)
      let clampedLimit = min(max(1, limit), 500)
      // Upper-bound the offset so the UInt32 narrowing below can never trap on a
      // hostile/huge `offset` (saturates instead of crashing).
      let clampedOffset = min(max(0, offset), Int(UInt32.max))
      let rows = try TaskRepo.Read.getScheduledTasks(
        db, today: today, limit: UInt32(clampedLimit), offset: UInt32(clampedOffset))
      let total = try TaskRepo.Read.countScheduledTasks(db, today: today)
      let tasks = try Self.enrich(db, rows: rows)
      return Self.pageResult(
        tasks: tasks, totalMatching: Int(total), limit: clampedLimit, offset: clampedOffset)
    }
  }

  public func listTasks(
    status: String,
    listID: LorvexList.ID?,
    priority: Int?,
    text: String?,
    limit: Int,
    offset: Int
  ) async throws -> TaskPageResult {
    return try read { db in
      let clampedLimit = min(max(1, limit), 500)
      // Upper-bound the offset so the UInt32 narrowing below can never trap on a
      // hostile/huge `offset` from an MCP client (saturates instead of crashing).
      let clampedOffset = min(max(0, offset), Int(UInt32.max))
      let query = TaskRepo.ListTasksQuery(
        listId: listID,
        status: Self.statusListFilter(status),
        priority: priority.map { UInt8(max(1, min(3, $0))) },
        text: text,
        limit: UInt32(clampedLimit),
        offset: UInt32(clampedOffset))
      let result = try TaskRepo.Read.listTasks(db, query: query)
      let tasks = try Self.enrich(db, rows: result.rows)
      return Self.pageResult(
        tasks: tasks, totalMatching: Int(result.totalMatching),
        limit: clampedLimit, offset: clampedOffset)
    }
  }

  public func listTasks(query request: TaskListQueryRequest) async throws -> TaskPageResult {
    return try read { db in
      let clampedLimit = min(max(1, request.limit), 500)
      let clampedOffset = max(0, request.offset)
      let availability = Self.availabilityFilter(request.availability)
      // `today` anchors the defer-until visibility predicate; only computed when
      // a non-`all` availability filter is requested (buildWhereClause ignores
      // it otherwise), so a plain list never pays the timezone lookup.
      let today = availability == .all ? nil : try WorkflowTimezone.todayYmdForConn(db)
      let query = TaskRepo.ListTasksQuery(
        listId: request.listID.trimmedNilIfEmpty,
        status: Self.statusListFilter(request.status),
        priority: request.priority.map { UInt8(max(1, min(3, $0))) },
        dueRange: Self.range(from: request.dueFrom, to: request.dueTo),
        plannedRange: Self.range(from: request.plannedFrom, to: request.plannedTo),
        scheduledRange: Self.range(from: request.scheduledFrom, to: request.scheduledTo),
        completedRange: Self.range(from: request.completedFrom, to: request.completedTo),
        createdRange: Self.range(from: request.createdFrom, to: request.createdTo),
        updatedRange: Self.range(from: request.updatedFrom, to: request.updatedTo),
        availableFromRange: Self.range(
          from: request.availableFromFrom, to: request.availableFromTo),
        duePresence: Self.dateFilter(request.duePresence),
        plannedPresence: Self.dateFilter(request.plannedPresence),
        availability: availability,
        today: today,
        tags: request.tags,
        text: request.text.trimmedNilIfEmpty,
        blocking: .fromFlags(
          blockedOnly: request.blockedOnly, blockingOthers: request.blockingOthers),
        sortBy: Self.taskListSortBy(request.sortBy),
        sortDirection: Self.sortDirection(request.sortDirection),
        limit: UInt32(clampedLimit),
        offset: UInt32(clampedOffset))
      let result = try TaskRepo.Read.listTasks(db, query: query)
      let tasks = try Self.enrich(db, rows: result.rows)
      return Self.pageResult(
        tasks: tasks, totalMatching: Int(result.totalMatching),
        limit: clampedLimit, offset: clampedOffset)
    }
  }

  public func searchTasks(query: String, status: String, limit: Int, offset: Int) async throws
    -> TaskSearchResult
  {
    return try read { db in
      let clampedLimit = min(max(1, limit), 500)
      // Upper-bound the offset so the UInt32 narrowing below can never trap on a
      // hostile/huge `offset` from an MCP client (saturates instead of crashing).
      let clampedOffset = min(max(0, offset), Int(UInt32.max))
      let predicate = SearchPredicate(
        query: query, statusFilter: Self.statusSearchFilter(status))
      let page = Pagination(limit: UInt32(clampedLimit), offset: UInt32(clampedOffset))
      let result = try TaskRepo.Search.searchTasksWithFallback(
        db, predicate: predicate, page: page)
      let tasks = try Self.enrich(db, rows: result.rows)
      let meta = Self.pagination(
        returned: tasks.count, totalMatching: Int(result.totalMatching),
        limit: clampedLimit, offset: clampedOffset)
      return TaskSearchResult(
        query: query,
        tasks: tasks,
        totalMatching: Int(result.totalMatching),
        returned: meta.returned,
        limit: clampedLimit,
        offset: clampedOffset,
        nextOffset: meta.nextOffset,
        truncated: meta.truncated)
    }
  }

  public func getDeferredTasks(listID: LorvexList.ID?, limit: Int, offset: Int) async throws
    -> TaskPageResult
  {
    try read { db in
      let clampedLimit = min(max(1, limit), 500)
      // Upper-bound the offset so the UInt32 narrowing below can never trap on a
      // hostile/huge `offset` from an MCP client (saturates instead of crashing).
      let clampedOffset = min(max(0, offset), Int(UInt32.max))
      let page = Pagination(limit: UInt32(clampedLimit), offset: UInt32(clampedOffset))
      let rows = try TaskRepo.Read.getDeferredTasks(db, listId: listID, page: page)
      let total = try TaskRepo.Read.countDeferredTasks(db, listId: listID)
      let tasks = try Self.enrich(db, rows: rows)
      return Self.pageResult(
        tasks: tasks, totalMatching: Int(total), limit: clampedLimit, offset: clampedOffset)
    }
  }

  public func getDueTaskReminders(asOf: String?, limit: Int) async throws -> [TaskReminderWithTask] {
    try read { db in
      let now = asOf ?? SyncTimestampFormat.syncTimestampNow()
      let result = try TaskRepo.Reminders.getDueTaskReminders(
        db, now: now, limit: UInt32(min(max(1, limit), 500)))
      return result.rows.map(Self.reminderWithTask)
    }
  }

  @discardableResult
  public func markDueTaskRemindersDelivered(asOf: Date) async throws -> Int {
    try write { db in
      try TaskRepo.Reminders.markDueRemindersDelivered(
        db, now: SyncTimestampFormat.formatSyncTimestamp(asOf))
    }
  }

  public func replaceArmedTaskReminders(reminderIDs: [String], asOf: Date) async throws {
    try write { db in
      try TaskRepo.Reminders.replaceRemindersArmed(
        db, armedReminderIDs: reminderIDs,
        armedAt: SyncTimestampFormat.formatSyncTimestamp(asOf))
    }
  }

  public func getUpcomingTaskReminders(hoursAhead: Int, limit: Int) async throws
    -> [TaskReminderWithTask]
  {
    try read { db in
      let now = Date()
      let horizon = now.addingTimeInterval(TimeInterval(max(1, hoursAhead) * 3600))
      let result = try TaskRepo.Reminders.getUpcomingTaskRemindersUntil(
        db,
        now: SyncTimestampFormat.formatSyncTimestamp(now),
        horizon: SyncTimestampFormat.formatSyncTimestamp(horizon),
        limit: UInt32(min(max(1, limit), 500)))
      return result.rows.map(Self.reminderWithTask)
    }
  }

  public func getTasksWithUpcomingReminders(hoursAhead: Int, limit: Int) async throws
    -> [LorvexTask]
  {
    try read { db in
      let now = Date()
      let horizon = now.addingTimeInterval(TimeInterval(max(1, hoursAhead) * 3600))
      let result = try TaskRepo.Reminders.getUpcomingTaskRemindersUntil(
        db,
        now: SyncTimestampFormat.formatSyncTimestamp(now),
        horizon: SyncTimestampFormat.formatSyncTimestamp(horizon),
        limit: UInt32(min(max(1, limit), 500)))
      var seen = Set<String>()
      var rows = [TaskRow]()
      for reminder in result.rows where seen.insert(reminder.taskId).inserted {
        if let task = try TaskRepo.Read.getTask(db, taskId: TaskId(trusted: reminder.taskId)) {
          rows.append(task)
        }
      }
      return try Self.enrich(db, rows: rows)
    }
  }

}
