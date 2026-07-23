import Foundation
import GRDB
import LorvexDomain

/// Shared Focus Schedule proposal planner.
///
/// The MCP host and CLI both expose a "propose schedule" read path; the
/// packing algorithm lives here so their slot/block semantics cannot drift.
/// The packer projects calendar events from
/// ``CalendarTimelineQueries/getDayBlockingRanges(_:date:anchorTimezone:accessMode:)``
/// into provenance-preserving display blocks, while separately unioning their
/// occupancy intervals for task placement and available-minute accounting.
/// Timezone/DST routing stays in the timeline reader's projection.
public enum FocusScheduleProposal {
  // MARK: - DTOs

  public struct WorkingHours: Sendable, Equatable {
    public var start: TimeOfDay
    public var end: TimeOfDay
  }

  public struct Task: Sendable, Equatable {
    public var id: String
    public var title: String
    public var status: String
    public var dueDate: LorvexDate?
    public var plannedDate: LorvexDate?
    public var priority: Int64?
    public var listId: String
    public var estimatedMinutes: Int64?
  }

  public struct Slot: Sendable, Equatable {
    public var task: Task
    public var startTime: TimeOfDay
    public var endTime: TimeOfDay
  }

  public struct Block: Sendable, Equatable {
    public var blockType: String
    public var startTime: TimeOfDay
    public var endTime: TimeOfDay
    public var taskId: String?
    public var calendarEventId: String?
    public var eventSource: FocusScheduleEventSource?
    public var title: String?
  }

  public struct Proposal: Sendable, Equatable {
    public var date: LorvexDate
    public var workingHours: WorkingHours
    public var totalMinutesAvailable: Int64
    public var calendarEventsCount: Int
    public var slots: [Slot]
    public var blocks: [Block]
    public var unscheduled: [Task]
  }

  // MARK: - Time helpers

  /// Render a typed `TimeOfDay` as the integer minute offset from midnight
  /// (0..=1440). Drops seconds.
  static func timeOfDayToMinutes(_ value: TimeOfDay) -> Int64 {
    Int64(value.minutesOfDay)
  }

  /// Convert minutes-from-midnight back into a typed `TimeOfDay`, saturating
  /// at 23:59.
  static func minutesToTimeOfDay(_ value: Int64) -> TimeOfDay {
    TimeOfDay.fromMinutesSaturating(Int(value))
  }

  private struct EventRange {
    var start: Int64
    var end: Int64
    var title: String
    var calendarEventId: String?
    var eventSource: FocusScheduleEventSource
  }

  /// Provenance-free union used only by the task packer. Keeping this distinct
  /// from ``EventRange`` prevents overlapping canonical/provider events from
  /// being collapsed into a fabricated source or losing canonical identity.
  private struct OccupancyRange {
    var start: Int64
    var end: Int64
  }

  private static func makeEventBlock(_ event: EventRange, start: Int64, end: Int64) -> Block {
    Block(
      blockType: "event",
      startTime: minutesToTimeOfDay(start),
      endTime: minutesToTimeOfDay(end),
      taskId: nil,
      calendarEventId: event.calendarEventId,
      eventSource: event.eventSource,
      title: event.title)
  }

  private static func mergedOccupancy(_ sortedEvents: [EventRange]) -> [OccupancyRange] {
    var merged: [OccupancyRange] = []
    merged.reserveCapacity(sortedEvents.count)
    for event in sortedEvents {
      if let lastIndex = merged.indices.last, event.start <= merged[lastIndex].end {
        merged[lastIndex].end = max(merged[lastIndex].end, event.end)
      } else {
        merged.append(OccupancyRange(start: event.start, end: event.end))
      }
    }
    return merged
  }

  private static func blockPrecedes(_ lhs: Block, _ rhs: Block) -> Bool {
    if lhs.startTime != rhs.startTime { return lhs.startTime < rhs.startTime }
    if lhs.endTime != rhs.endTime { return lhs.endTime > rhs.endTime }
    func typeRank(_ type: String) -> Int {
      switch type {
      case "event": 0
      case "task": 1
      case "buffer": 2
      default: 3
      }
    }
    let lhsTypeRank = typeRank(lhs.blockType)
    let rhsTypeRank = typeRank(rhs.blockType)
    if lhsTypeRank != rhsTypeRank { return lhsTypeRank < rhsTypeRank }
    let lhsSource = lhs.eventSource?.rawValue ?? ""
    let rhsSource = rhs.eventSource?.rawValue ?? ""
    if lhsSource != rhsSource { return lhsSource < rhsSource }
    let lhsIdentity = lhs.calendarEventId ?? lhs.taskId ?? lhs.title ?? ""
    let rhsIdentity = rhs.calendarEventId ?? rhs.taskId ?? rhs.title ?? ""
    return lhsIdentity < rhsIdentity
  }

  // MARK: - Orchestrator

  /// `workingHoursStart`/`workingHoursEnd` (HH:MM) override the stored
  /// working-hours preference for this proposal only; each side falls back to
  /// the preference independently. `includeCalendarEvents: false` skips the
  /// day's blocking ranges, scheduling as if the calendar were empty.
  public static func proposeFocusSchedule(
    _ db: Database,
    date: String,
    anchorTimezone: String,
    accessMode: CalendarAiAccessMode,
    workingHoursStart: String? = nil,
    workingHoursEnd: String? = nil,
    includeCalendarEvents: Bool = true
  ) throws -> Proposal {
    let parsedDate: LorvexDate
    switch LorvexDate.parse(date) {
    case .success(let value): parsedDate = value
    case .failure:
      throw StoreError.validation("invalid focus schedule date: \(date)")
    }

    var workingHours = try loadWorkingHours(db)
    if let workingHoursStart {
      switch TimeOfDay.parse(workingHoursStart) {
      case .success(let value): workingHours = WorkingHours(start: value, end: workingHours.end)
      case .failure:
        throw StoreError.validation(
          "working_hours_start must be HH:MM, got '\(workingHoursStart)'")
      }
    }
    if let workingHoursEnd {
      switch TimeOfDay.parse(workingHoursEnd) {
      case .success(let value): workingHours = WorkingHours(start: workingHours.start, end: value)
      case .failure:
        throw StoreError.validation(
          "working_hours_end must be HH:MM, got '\(workingHoursEnd)'")
      }
    }
    let startMinutes = timeOfDayToMinutes(workingHours.start)
    let endMinutes = timeOfDayToMinutes(workingHours.end)
    if endMinutes < startMinutes {
      throw StoreError.validation("working_hours.end must be after working_hours.start")
    }

    let focusTaskIds = try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: date)
    if focusTaskIds.isEmpty {
      throw StoreError.validation(
        "no current focus set for this date; set focus tasks before proposing a schedule")
    }

    let tasks = try loadTaskCandidates(
      db, taskIds: focusTaskIds, asOf: parsedDate.asString)
    if tasks.isEmpty {
      throw StoreError.validation("current focus has no open active tasks to schedule")
    }

    let blocking =
      includeCalendarEvents
      ? try CalendarTimelineQueries.getDayBlockingRanges(
        db, date: date, anchorTimezone: anchorTimezone, accessMode: accessMode)
      : []

    var eventRanges: [EventRange] = []
    eventRanges.reserveCapacity(blocking.count)
    for range in blocking {
      if range.endMinutes <= startMinutes || range.startMinutes >= endMinutes {
        continue
      }
      let clippedStart = max(range.startMinutes, startMinutes)
      let clippedEnd = min(range.endMinutes, endMinutes)
      eventRanges.append(
        EventRange(
          start: clippedStart,
          end: clippedEnd,
          title: range.title,
          calendarEventId: range.canonicalEventId,
          eventSource: range.source == .canonical ? .canonical : .provider))
    }
    let occupancy = mergedOccupancy(eventRanges)
    let totalEventMinutes = occupancy.reduce(Int64(0)) { partial, range in
      partial + (range.end - range.start)
    }
    let calendarEventsCount = eventRanges.count

    var state = ProposalState(
      occupancy: occupancy,
      startMinutes: startMinutes,
      endMinutes: endMinutes)
    var unscheduled: [Task] = []
    unscheduled.reserveCapacity(tasks.count)

    for task in tasks {
      let duration: Int64 = {
        if let est = task.estimatedMinutes, est > 0 { return est }
        return 30
      }()
      state.advancePastOccupancy()

      if state.cursor + duration > state.availableUntil() {
        if !state.tryScheduleLater(task, duration: duration) {
          unscheduled.append(task)
        }
        continue
      }

      state.placeTask(task, duration: duration)
    }

    var blocks = eventRanges.map { event in
      makeEventBlock(event, start: event.start, end: event.end)
    }
    blocks.append(contentsOf: state.blocks)
    blocks.sort(by: blockPrecedes)

    return Proposal(
      date: parsedDate,
      workingHours: workingHours,
      totalMinutesAvailable: endMinutes - startMinutes - totalEventMinutes,
      calendarEventsCount: calendarEventsCount,
      slots: state.slots,
      blocks: blocks,
      unscheduled: unscheduled)
  }

  // MARK: - Packing state machine

  private struct ProposalState {
    let occupancy: [OccupancyRange]
    var occupancyIndex = 0
    var cursor: Int64
    let endMinutes: Int64
    let bufferMinutes: Int64 = 10
    var slots: [Slot] = []
    var blocks: [Block] = []

    init(occupancy: [OccupancyRange], startMinutes: Int64, endMinutes: Int64) {
      self.occupancy = occupancy
      self.endMinutes = endMinutes
      self.cursor = startMinutes
    }

    mutating func advancePastOccupancy() {
      while occupancyIndex < occupancy.count, occupancy[occupancyIndex].start <= cursor {
        cursor = max(cursor, occupancy[occupancyIndex].end)
        occupancyIndex += 1
      }
    }

    func availableUntil() -> Int64 {
      let next = occupancyIndex < occupancy.count ? occupancy[occupancyIndex].start : endMinutes
      return min(next, endMinutes)
    }

    mutating func placeTask(_ task: Task, duration: Int64) {
      let start = minutesToTimeOfDay(cursor)
      let end = minutesToTimeOfDay(cursor + duration)
      slots.append(Slot(task: task, startTime: start, endTime: end))
      blocks.append(
        Block(
          blockType: "task",
          startTime: start,
          endTime: end,
          taskId: task.id,
          calendarEventId: nil,
          eventSource: nil,
          title: nil))
      cursor += duration

      let availableUntil = availableUntil()
      if cursor + bufferMinutes <= availableUntil {
        let startTime = minutesToTimeOfDay(cursor)
        let endTime = minutesToTimeOfDay(cursor + bufferMinutes)
        blocks.append(
          Block(
            blockType: "buffer",
            startTime: startTime,
            endTime: endTime,
            taskId: nil,
            calendarEventId: nil,
            eventSource: nil,
            title: nil))
        cursor += bufferMinutes
      }
    }

    mutating func tryScheduleLater(_ task: Task, duration: Int64) -> Bool {
      var probeCursor = cursor
      var probeIndex = occupancyIndex

      while probeIndex < occupancy.count {
        probeCursor = max(probeCursor, occupancy[probeIndex].end)
        probeIndex += 1

        let nextBoundary =
          probeIndex < occupancy.count ? occupancy[probeIndex].start : endMinutes

        if probeCursor + duration <= min(nextBoundary, endMinutes) {
          occupancyIndex = probeIndex
          cursor = probeCursor
          placeTask(task, duration: duration)
          return true
        }
      }
      return false
    }
  }

  // MARK: - SQL loaders

  /// Load the open, non-archived focus tasks eligible for auto-scheduling.
  ///
  /// Tasks hidden by `available_from` on `asOf` (defer-until, overdue-wins) are
  /// excluded: the auto-proposal must not schedule a task the user hid until
  /// later. A hidden task can still be added to the focus set manually — this
  /// gate only governs the generated schedule. `asOf` is the canonical
  /// `YYYY-MM-DD` day the schedule is being proposed for.
  static func loadTaskCandidates(
    _ db: Database, taskIds: [String], asOf: String
  ) throws -> [Task] {
    let placeholders = Sql.sqlInPlaceholders(taskIds.count, 0)
    let asOfPlaceholder = "?\(taskIds.count + 1)"
    let visible = TaskReadBuckets.availableVisibilityPredicate(
      taskAlias: "tasks", datePlaceholder: asOfPlaceholder)
    let sql = """
      SELECT id, title, status, due_date, planned_date, priority, list_id, estimated_minutes \
      FROM tasks \
      WHERE id IN (\(placeholders)) \
        AND status IN (\(StatusName.actionableStatusSqlList)) \
        AND archived_at IS NULL \
        AND \(visible) \
      ORDER BY \(TaskRepo.taskOrderBy)
      """
    var args: [DatabaseValueConvertible?] = taskIds
    args.append(asOf)
    let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
    return try rows.map { row in
      Task(
        id: row[0],
        title: row[1],
        status: row[2],
        dueDate: try parseDate(row, 3),
        plannedDate: try parseDate(row, 4),
        priority: row[5],
        listId: row[6],
        estimatedMinutes: row[7])
    }
  }

  private static func parseDate(_ row: Row, _ index: Int) throws -> LorvexDate? {
    guard let raw: String = row[index] else { return nil }
    switch LorvexDate.parse(raw) {
    case .success(let value): return value
    case .failure:
      throw DatabaseError(
        resultCode: .SQLITE_MISMATCH, message: "tasks: invalid date '\(raw)'")
    }
  }

  static func loadWorkingHours(_ db: Database) throws -> WorkingHours {
    let raw = try String.fetchOne(
      db, sql: "SELECT value FROM preferences WHERE key = ?1",
      arguments: [PreferenceKeys.prefWorkingHours])

    guard let raw else {
      let start = parseRequired(Defaults.workingHoursStart)
      let end = parseRequired(Defaults.workingHoursEnd)
      return WorkingHours(start: start, end: end)
    }

    // Two accepted shapes, mirroring how preferences store the value: the JSON
    // object `{"start":"HH:MM","end":"HH:MM"}` (written by the settings UI) and
    // the hyphen string `"HH:MM-HH:MM"` (the seeded/default form, stored
    // verbatim by `complete_setup` / `set_preference` as a JSON string literal).
    // The object form is tried first; a parsed JSON *string* falls back to the
    // hyphen-window form before throwing.
    //
    // The hyphen-string fallback is intentional because the default/stored
    // value is the hyphen string. When neither form parses, this throws
    // `working_hours preference must be a JSON object with string start/end`.
    let parsed = JSONValue.parse(raw)
    if case .object(let obj)? = parsed,
      case .string(let startStr)? = obj["start"],
      case .string(let endStr)? = obj["end"]
    {
      return try makeWorkingHours(startStr, endStr)
    }
    if case .string(let inner)? = parsed, let (startStr, endStr) = parseHyphenWindow(inner) {
      return try makeWorkingHours(startStr, endStr)
    }
    throw StoreError.validation(
      "working_hours preference must be a JSON object with string start/end")
  }

  /// Split a `"HH:MM-HH:MM"` working-hours window into its two halves, or `nil`
  /// when the value is not exactly one hyphen-separated pair. Time-of-day
  /// validity is left to ``makeWorkingHours(_:_:)``.
  private static func parseHyphenWindow(_ raw: String) -> (String, String)? {
    let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    return (String(parts[0]), String(parts[1]))
  }

  /// Validate a start/end pair (each `HH:MM`, end at or after start) into a
  /// ``WorkingHours``. Shared by the object and hyphen-string read paths.
  private static func makeWorkingHours(_ startStr: String, _ endStr: String) throws -> WorkingHours {
    let start: TimeOfDay
    switch TimeOfDay.parse(startStr) {
    case .success(let value): start = value
    case .failure:
      throw StoreError.validation("working_hours.start must be HH:MM, got '\(startStr)'")
    }
    let end: TimeOfDay
    switch TimeOfDay.parse(endStr) {
    case .success(let value): end = value
    case .failure:
      throw StoreError.validation("working_hours.end must be HH:MM, got '\(endStr)'")
    }
    if timeOfDayToMinutes(end) < timeOfDayToMinutes(start) {
      throw StoreError.validation("working_hours.end must be after working_hours.start")
    }
    return WorkingHours(start: start, end: end)
  }

  private static func parseRequired(_ raw: String) -> TimeOfDay {
    switch TimeOfDay.parse(raw) {
    case .success(let value): return value
    case .failure:
      preconditionFailure("default working hours constant must parse as HH:MM")
    }
  }
}
