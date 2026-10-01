import Foundation
import GRDB
import LorvexDomain

/// Suggested times for one day: the day's tasks laid into its free working
/// time, around calendar events.
///
/// The assistant's `propose_daily_schedule` and the apps' Suggest Times both
/// read their suggestion from here, so they cannot drift. Calendar events come
/// from ``CalendarTimelineQueries/getDayBlockingRanges(_:date:anchorTimezone:accessMode:)``
/// and are returned for display with their provenance, while their occupancy
/// is merged separately for placement and available-minute accounting.
/// Timezone and DST routing stay in the timeline reader's projection. Nothing
/// is stored: a caller that accepts the suggestion saves the slots as the
/// tasks' times.
public enum DayScheduleProposal {
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
    /// The task's saved time on its planned day, in minutes since midnight.
    public var plannedTime: Range<Int64>?
  }

  /// A task and the time the suggestion gives it, in minutes since midnight.
  public struct Slot: Sendable, Equatable {
    public var task: Task
    public var start: Int64
    public var end: Int64
  }

  /// Where a calendar event the suggestion worked around comes from: a synced
  /// Lorvex event (with its id) or an event of a calendar on this device.
  public enum EventSource: String, Sendable, Equatable {
    case canonical
    case provider
  }

  /// A calendar event inside the working window, in minutes since midnight,
  /// with the title the access mode allows.
  public struct Event: Sendable, Equatable {
    public var start: Int64
    public var end: Int64
    public var title: String
    public var calendarEventId: String?
    public var source: EventSource
  }

  public struct Proposal: Sendable, Equatable {
    public var date: LorvexDate
    public var workingHours: WorkingHours
    /// Working minutes left free by the events, from the suggestion's start.
    public var totalMinutesAvailable: Int64
    /// The placed tasks, in start order.
    public var slots: [Slot]
    /// The events inside the working window, in start order.
    public var events: [Event]
    /// The tasks that did not fit, in the day's order.
    public var unscheduled: [Task]
  }

  /// Minutes a task without an estimate or a saved time takes.
  public static let defaultTaskMinutes: Int64 = 30

  /// The gap left after each placed task when the whole gap fits before the
  /// free time the task was placed in ends (the next event or the end of
  /// working hours).
  static let breakMinutes: Int64 = 10

  // MARK: - Time helpers

  /// Render a typed `TimeOfDay` as the integer minute offset from midnight
  /// (0..=1440). Drops seconds.
  static func timeOfDayToMinutes(_ value: TimeOfDay) -> Int64 {
    Int64(value.minutesOfDay)
  }

  /// Provenance-free union used only by the task packer, so overlapping
  /// canonical and provider events are never collapsed into one fabricated
  /// event.
  private struct OccupancyRange {
    var start: Int64
    var end: Int64
  }

  private static func mergedOccupancy(_ sortedEvents: [Event]) -> [OccupancyRange] {
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

  private static func eventPrecedes(_ lhs: Event, _ rhs: Event) -> Bool {
    if lhs.start != rhs.start { return lhs.start < rhs.start }
    if lhs.end != rhs.end { return lhs.end > rhs.end }
    if lhs.source != rhs.source { return lhs.source.rawValue < rhs.source.rawValue }
    return (lhs.calendarEventId ?? lhs.title) < (rhs.calendarEventId ?? rhs.title)
  }

  // MARK: - Orchestrator

  /// The candidates are the day's tasks exactly as
  /// ``TaskRepo/Read/getTodayPoolTasks(_:today:)`` returns them for `date`:
  /// started tasks first, then canonical order. In that order, each task takes
  /// the start of the earliest free time long enough to hold it, so a short
  /// task can use a gap before an event that a longer task ahead of it did not
  /// fit, while a task earlier in the order always chooses first. A task takes
  /// its estimate, else the length of its saved time, else
  /// ``defaultTaskMinutes``, and a short break follows each placed task when it
  /// fits. A day with no open tasks comes back with no placements and no
  /// unscheduled tasks, still listing its events.
  ///
  /// `workingHoursStart`/`workingHoursEnd` (HH:MM) override the stored
  /// working-hours preference for this suggestion only; each side falls back
  /// to the preference independently. `includeCalendarEvents: false` skips the
  /// day's blocking ranges, suggesting as if the calendar were empty.
  ///
  /// `notBefore` is the earliest time of day work may be placed, which a
  /// caller suggesting the rest of today sets to the current time. Tasks pack
  /// from the later of it and the working-hours start. Events that end by then
  /// are left out; an event already under way keeps its real start while only
  /// its remaining minutes count as occupied. A task whose saved time on
  /// `date` is under way at `notBefore` keeps that time, and the other tasks
  /// are placed after it. Every other saved time is replaced by the suggestion.
  /// When no working time remains, every task comes back unscheduled.
  public static func propose(
    _ db: Database,
    date: String,
    anchorTimezone: String,
    accessMode: CalendarAiAccessMode,
    workingHoursStart: String? = nil,
    workingHoursEnd: String? = nil,
    includeCalendarEvents: Bool = true,
    notBefore: TimeOfDay? = nil
  ) throws -> Proposal {
    let parsedDate: LorvexDate
    switch LorvexDate.parse(date) {
    case .success(let value): parsedDate = value
    case .failure:
      throw StoreError.validation("invalid schedule date: \(date)")
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
    // The part of the working window tasks may still use.
    let windowStart = min(
      max(startMinutes, notBefore.map(timeOfDayToMinutes) ?? startMinutes), endMinutes)
    let hasWindow = windowStart < endMinutes

    // A day with nothing to place still returns its events and working
    // window, so a caller sees the calendar it would plan around.
    let tasks = try TaskRepo.Read.getTodayPoolTasks(db, today: parsedDate.asString)
      .map(Task.init(row:))

    let blocking =
      includeCalendarEvents
      ? try CalendarTimelineQueries.getDayBlockingRanges(
        db, date: date, anchorTimezone: anchorTimezone, accessMode: accessMode)
      : []

    var events: [Event] = []
    events.reserveCapacity(blocking.count)
    for range in blocking where hasWindow {
      if range.endMinutes <= windowStart || range.startMinutes >= endMinutes {
        continue
      }
      events.append(
        Event(
          start: max(range.startMinutes, startMinutes),
          end: min(range.endMinutes, endMinutes),
          title: range.title,
          calendarEventId: range.canonicalEventId,
          source: range.source == .canonical ? .canonical : .provider))
    }
    events.sort(by: eventPrecedes)
    // An event under way occupies only what is left of it.
    let occupancy = mergedOccupancy(
      events.map { event in
        var remaining = event
        remaining.start = max(event.start, windowStart)
        return remaining
      })
    let totalEventMinutes = occupancy.reduce(Int64(0)) { partial, range in
      partial + (range.end - range.start)
    }

    // The saved time the user is working through right now stays put.
    var underWay: (task: Task, start: Int64, end: Int64)?
    if let notBefore, hasWindow {
      let now = timeOfDayToMinutes(notBefore)
      let running = tasks.filter { task in
        task.plannedDate?.asString == parsedDate.asString
          && task.plannedTime.map { $0.contains(now) } ?? false
      }
      if let task = running.min(by: { $0.plannedTime!.lowerBound < $1.plannedTime!.lowerBound }),
        let time = task.plannedTime
      {
        let start = max(time.lowerBound, startMinutes)
        let end = min(time.upperBound, endMinutes)
        if end > windowStart { underWay = (task, start, end) }
      }
    }

    var free = FreeTime(from: windowStart, until: endMinutes, occupied: occupancy)
    if let underWay {
      free.take(underWay.task, from: underWay.start, until: underWay.end)
    }
    var unscheduled: [Task] = []
    unscheduled.reserveCapacity(tasks.count)

    for task in tasks where task.id != underWay?.task.id {
      let duration: Int64 = {
        if let estimate = task.estimatedMinutes, estimate > 0 { return estimate }
        if let time = task.plannedTime, !time.isEmpty { return time.upperBound - time.lowerBound }
        return defaultTaskMinutes
      }()
      if let start = free.earliestStart(holding: duration) {
        free.take(task, from: start, until: start + duration)
      } else {
        unscheduled.append(task)
      }
    }

    return Proposal(
      date: parsedDate,
      workingHours: workingHours,
      totalMinutesAvailable: endMinutes - windowStart - totalEventMinutes,
      slots: free.slots.sorted { $0.start < $1.start },
      events: events,
      unscheduled: unscheduled)
  }

  // MARK: - Free time

  /// The working time still free for tasks: disjoint ranges in minutes since
  /// midnight, in start order. A task takes the start of the earliest range
  /// long enough to hold it, and the time it takes, with the break after it,
  /// comes out of that range.
  private struct FreeTime {
    private var ranges: [Range<Int64>]
    private(set) var slots: [Slot] = []

    /// The window `[start, end)` less `occupied`, which is merged and in start
    /// order.
    init(from start: Int64, until end: Int64, occupied: [OccupancyRange]) {
      var ranges: [Range<Int64>] = []
      var cursor = start
      for range in occupied where range.end > cursor {
        if range.start > cursor { ranges.append(cursor..<min(range.start, end)) }
        cursor = range.end
      }
      if cursor < end { ranges.append(cursor..<end) }
      self.ranges = ranges.filter { !$0.isEmpty }
    }

    /// The start of the earliest free range that holds `duration` minutes.
    func earliestStart(holding duration: Int64) -> Int64? {
      ranges.first { $0.upperBound - $0.lowerBound >= duration }?.lowerBound
    }

    /// Records `task` over `[start, end)` and takes that time out of every free
    /// range it overlaps. A break follows the task when the whole break fits
    /// before its range ends; otherwise the minutes left stay free, so a task
    /// that short can still use them.
    mutating func take(_ task: Task, from start: Int64, until end: Int64) {
      slots.append(Slot(task: task, start: start, end: end))
      ranges = ranges.flatMap { range -> [Range<Int64>] in
        guard range.overlaps(start..<end) else { return [range] }
        var pieces: [Range<Int64>] = []
        if range.lowerBound < start { pieces.append(range.lowerBound..<start) }
        if end < range.upperBound {
          let afterBreak = end + DayScheduleProposal.breakMinutes
          let resume = afterBreak <= range.upperBound ? afterBreak : end
          if resume < range.upperBound { pieces.append(resume..<range.upperBound) }
        }
        return pieces
      }
    }
  }

  // MARK: - Working hours

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

extension DayScheduleProposal.Task {
  init(row: TaskRow) {
    self.init(
      id: row.core.id,
      title: row.core.title,
      status: row.core.status,
      dueDate: row.scheduling.dueDate,
      plannedDate: row.scheduling.plannedDate,
      priority: row.core.priority,
      listId: row.core.listId,
      estimatedMinutes: row.scheduling.estimatedMinutes,
      plannedTime: row.scheduling.plannedTime)
  }
}
