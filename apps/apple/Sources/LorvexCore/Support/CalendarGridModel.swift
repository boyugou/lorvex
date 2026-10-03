import Foundation

/// Pure day-column layout assembly: takes a contiguous date range's events +
/// scheduled tasks and produces fully laid-out day columns. Free of SwiftUI so
/// it stays cheap, testable, and shared between the macOS week grid and the
/// iPhone day / 3-day view.
///
/// Layout rules:
/// - All-day events (`startTime == nil`) go to the all-day strip on each day
///   their `[startDate, endDate]` span intersects within the range, and so do
///   timed events that last 24 hours or more, on each day they take time on.
/// - Shorter timed events are clipped per day: an event spanning Mon 22:00 →
///   Tue 01:00 yields a Mon 22:00–24:00 block and a Tue 00:00–01:00 block, each
///   marked with the part of the event it draws (``CalendarEventDayPart``). A
///   timed event missing `endTime` is given a default 60-minute duration.
/// - Overlap lanes are packed from the real times, so touching neighbours
///   stack. A block shorter than `minBlockMinutes` is drawn to that height
///   (`drawnEndMin`) only when nothing starts within that window below it.
/// - A task with a time (``LorvexTask/plannedTime``) renders on the time axis of
///   its planned day as a `CalendarGridTaskBlock`, sharing the day's overlap
///   lanes with the timed events. A task without a time renders in the all-day
///   strip on its planned day (falling back to its due day). A completed task
///   keeps its block, marked done, so the day's record stays readable; a
///   cancelled task is not drawn, and a task passed twice is drawn once.
public enum CalendarGridModel {
  public static let defaultEventDurationMinutes = 60
  /// The most scheduled tasks a calendar window loads
  /// (``LorvexTaskServicing/getScheduledTasks(from:to:limit:)``). The read
  /// counts finished tasks too and keeps the first rows in the canonical task
  /// order, not by day, so a cap a busy window can reach would drop tasks
  /// from scattered days; this one leaves room for a month view's three
  /// months of planned and finished work.
  public static let windowTaskLimit = 2_000
  /// The height, in minutes, a shorter block is drawn at when nothing starts
  /// within that window below it.
  public static let minBlockMinutes = 20

  public static func parseMinutes(_ hhmm: String?) -> Int? {
    guard let hhmm else { return nil }
    let parts = hhmm.split(separator: ":")
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
    guard (0..<24).contains(h), (0..<60).contains(m) else { return nil }
    return h * 60 + m
  }

  /// Canonical civil day for the calendar lane. Planning is authoritative when
  /// present; a deadline is the fallback for otherwise-unplanned work. Task day
  /// values are stored as UTC-midnight `Date`s, so format the original instant
  /// in UTC rather than converting it through the device calendar (which would
  /// move midnight to the previous day in time zones west of UTC).
  public static func scheduledTaskDayKey(_ task: LorvexTask) -> String? {
    guard let actionDate = task.plannedDate ?? task.dueDate else { return nil }
    return LorvexDateFormatters.ymdUTC.string(from: actionDate)
  }

  /// Builds `dayCount` contiguous day columns starting at `rangeStart`
  /// (a start-of-day Date). `dayKeyFor` formats a Date to the `yyyy-MM-dd`
  /// key used by event `startDate`/`endDate`. `dayCount` is 7 for the macOS
  /// week grid, 1 or 3 for the iPhone day / 3-day view.
  public static func buildDays(
    rangeStart: Date,
    dayCount: Int,
    calendar: Calendar,
    events: [CalendarTimelineEvent],
    tasks: [LorvexTask],
    dayKeyFor: (Date) -> String
  ) -> [CalendarGridDay] {
    let dayDates: [Date] = (0..<max(dayCount, 0)).compactMap {
      calendar.date(byAdding: .day, value: $0, to: rangeStart)
    }
    let dayKeys = dayDates.map(dayKeyFor)
    let keySet = Set(dayKeys)

    var allDayByKey: [String: [CalendarTimelineEvent]] = [:]
    // For each day key, the timed intervals clipped to that day.
    var intervalsByKey: [String: [CalendarGridLayout.Interval]] = [:]
    var eventByBlockID: [String: CalendarTimelineEvent] = [:]

    for event in events {
      let startKey = event.startDate
      let endKey = event.endDate ?? event.startDate

      if event.allDay {
        // Spread across each day in the span that falls in this range.
        for key in dayKeys where event.occurs(on: key) {
          allDayByKey[key, default: []].append(event)
        }
        continue
      }

      guard let startMinRaw = parseMinutes(event.startTime) else {
        // Timed flag but no parseable start -> treat as all-day on start day.
        if keySet.contains(startKey) {
          allDayByKey[startKey, default: []].append(event)
        }
        continue
      }
      let endMinRaw = parseMinutes(event.endTime) ?? (startMinRaw + defaultEventDurationMinutes)

      // An event of a day or more reads as days, as on Apple's calendars: it
      // joins the all-day strip on each day it takes time on rather than
      // filling those days' time axes and narrowing everything beside it.
      let wallMinutes =
        CalendarEventTiming.daySpan(startDate: startKey, endDate: event.endDate) * 1440
        + endMinRaw - startMinRaw
      if wallMinutes >= 1440 {
        for key in dayKeys where event.occurs(on: key) {
          allDayByKey[key, default: []].append(event)
        }
        continue
      }

      if startKey == endKey {
        guard keySet.contains(startKey) else { continue }
        let blockID = "\(event.id)#\(startKey)"
        intervalsByKey[startKey, default: []].append(
          .init(id: blockID, startMin: startMinRaw, endMin: min(max(endMinRaw, startMinRaw + 1), 1440))
        )
        eventByBlockID[blockID] = event
        continue
      }

      // A timed event shorter than a day that runs into the next day: clip it
      // to each day it takes time on, which leaves out the end day of an event
      // ending at exactly midnight rather than drawing a minimum-height sliver
      // at 00:00 there.
      for key in dayKeys where event.occurs(on: key) {
        let startMin = key == startKey ? startMinRaw : 0
        let endMin = key == endKey ? max(endMinRaw, 1) : 1440
        let blockID = "\(event.id)#\(key)"
        intervalsByKey[key, default: []].append(
          .init(id: blockID, startMin: startMin, endMin: min(max(endMin, startMin + 1), 1440))
        )
        eventByBlockID[blockID] = event
      }
    }

    // Timed tasks share the day's lanes with its timed events.
    var taskByBlockID: [String: LorvexTask] = [:]
    var tasksByKey: [String: [LorvexTask]] = [:]
    var seenTaskIDs = Set<LorvexTask.ID>()
    for task in tasks where task.status != .cancelled && seenTaskIDs.insert(task.id).inserted {
      if let plannedDate = task.plannedDate, let time = task.plannedTime {
        let key = LorvexDateFormatters.ymdUTC.string(from: plannedDate)
        guard keySet.contains(key) else { continue }
        let blockID = "task:\(task.id)#\(key)"
        intervalsByKey[key, default: []].append(
          .init(
            id: blockID, startMin: time.lowerBound,
            endMin: min(max(time.upperBound, time.lowerBound + 1), 1440)))
        taskByBlockID[blockID] = task
        continue
      }
      guard let key = scheduledTaskDayKey(task), keySet.contains(key) else { continue }
      tasksByKey[key, default: []].append(task)
    }

    return zip(dayDates, dayKeys).map { date, key in
      let intervals = intervalsByKey[key] ?? []
      let placed = CalendarGridLayout.layoutLanes(intervals)
      let drawnEnds = CalendarGridLayout.drawnEndMinutes(intervals, minimumMinutes: minBlockMinutes)
      var blocks: [CalendarGridTimedBlock] = []
      var taskBlocks: [CalendarGridTaskBlock] = []
      for p in placed {
        if let event = eventByBlockID[p.id] {
          blocks.append(
            CalendarGridTimedBlock(
              event: event,
              startMin: p.startMin,
              endMin: p.endMin,
              drawnEndMin: drawnEnds[p.id] ?? p.endMin,
              lane: p.lane,
              laneCount: p.laneCount,
              id: p.id,
              part: event.dayPart(on: key)
            ))
        } else if let task = taskByBlockID[p.id] {
          taskBlocks.append(
            CalendarGridTaskBlock(
              task: task,
              startMin: p.startMin,
              endMin: p.endMin,
              drawnEndMin: drawnEnds[p.id] ?? p.endMin,
              lane: p.lane,
              laneCount: p.laneCount,
              id: p.id
            ))
        }
      }
      let allDay = (allDayByKey[key] ?? []).sorted {
        $0.title.localizedStandardCompare($1.title) == .orderedAscending
      }
      return CalendarGridDay(
        date: date,
        dayKey: key,
        timedBlocks: blocks,
        allDayEvents: allDay,
        scheduledTasks: tasksByKey[key] ?? [],
        taskBlocks: taskBlocks
      )
    }
  }

  /// Chooses the hour row a scrollable time-axis view should reveal first.
  ///
  /// When today is among `days` and `nowMinute` is known, opens one hour before
  /// the current time so the now-line is in view on launch (matching first-party
  /// Calendar) — unless today has a timed event or task starting before
  /// that now-anchor, in which case it opens at that earliest block's hour so an
  /// early-morning appointment isn't scrolled off the top when the day is opened
  /// in the afternoon. Otherwise, if the visible days contain pre-workday timed
  /// content the anchor moves to midnight; failing that it opens at
  /// `fallbackHour`.
  ///
  /// `todayKey`/`nowMinute` are the `yyyy-MM-dd` key and minutes-since-midnight
  /// of the current moment; both nil reproduces the content-only behavior.
  public static func initialScrollAnchorHour(
    for days: [CalendarGridDay],
    todayKey: String? = nil,
    nowMinute: Int? = nil,
    fallbackHour: Int = 8
  ) -> Int {
    if let todayKey, let nowMinute, days.contains(where: { $0.dayKey == todayKey }) {
      let nowAnchorHour = max(0, nowMinute / 60 - 1)
      let todaysEarliestHour =
        days
        .first(where: { $0.dayKey == todayKey })?
        .earliestBlockStart
        .map { $0 / 60 }
      if let todaysEarliestHour, todaysEarliestHour < nowAnchorHour {
        return todaysEarliestHour
      }
      return nowAnchorHour
    }
    let fallbackMinute = max(0, min(23, fallbackHour)) * 60
    let earliest = days.compactMap(\.earliestBlockStart).min()
    guard let earliest, earliest < fallbackMinute else {
      return fallbackMinute / 60
    }
    return 0
  }

  /// Start of the week (respecting `calendar.firstWeekday`) containing `date`.
  public static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
    let startOfDay = calendar.startOfDay(for: date)
    let weekday = calendar.component(.weekday, from: startOfDay)
    let diff = (weekday - calendar.firstWeekday + 7) % 7
    return calendar.date(byAdding: .day, value: -diff, to: startOfDay) ?? startOfDay
  }
}
