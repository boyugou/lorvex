import Foundation

/// Pure day-column layout assembly: takes a contiguous date range's events +
/// scheduled tasks and produces fully laid-out day columns. Free of SwiftUI so
/// it stays cheap, testable, and shared between the macOS week grid and the
/// iPhone day / 3-day view.
///
/// Layout rules:
/// - All-day events (`startTime == nil`) go to the all-day strip on each day
///   their `[startDate, endDate]` span intersects within the range.
/// - Timed events are clipped per day: an event spanning Mon 22:00 → Tue 01:00
///   yields a Mon 22:00–24:00 block and a Tue 00:00–01:00 block. A timed event
///   missing `endTime` is given a default 60-minute duration.
/// - `LorvexTask` has no intra-day start, so scheduled tasks render in the
///   all-day strip on their planned day (falling back to due day), never as
///   positioned blocks.
public enum CalendarGridModel {
  public static let defaultEventDurationMinutes = 60
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
        for key in dayKeys where key >= startKey && key <= endKey {
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

      if startKey == endKey {
        guard keySet.contains(startKey) else { continue }
        let clampedEnd = max(endMinRaw, startMinRaw + minBlockMinutes)
        let blockID = "\(event.id)#\(startKey)"
        intervalsByKey[startKey, default: []].append(
          .init(id: blockID, startMin: startMinRaw, endMin: min(clampedEnd, 1440))
        )
        eventByBlockID[blockID] = event
        continue
      }

      // Multi-day timed event: clip per day across the span.
      for key in dayKeys where key >= startKey && key <= endKey {
        let startMin = key == startKey ? startMinRaw : 0
        let endMin = key == endKey ? max(endMinRaw, 1) : 1440
        let clampedEnd = max(endMin, startMin + minBlockMinutes)
        let blockID = "\(event.id)#\(key)"
        intervalsByKey[key, default: []].append(
          .init(id: blockID, startMin: startMin, endMin: min(clampedEnd, 1440))
        )
        eventByBlockID[blockID] = event
      }
    }

    var tasksByKey: [String: [LorvexTask]] = [:]
    for task in tasks {
      guard let key = scheduledTaskDayKey(task) else { continue }
      if keySet.contains(key) {
        tasksByKey[key, default: []].append(task)
      }
    }

    return zip(dayDates, dayKeys).map { date, key in
      let placed = CalendarGridLayout.layoutLanes(intervalsByKey[key] ?? [])
      let blocks = placed.compactMap { p -> CalendarGridTimedBlock? in
        guard let event = eventByBlockID[p.id] else { return nil }
        return CalendarGridTimedBlock(
          event: event,
          startMin: p.startMin,
          endMin: p.endMin,
          lane: p.lane,
          laneCount: p.laneCount,
          id: p.id
        )
      }
      let allDay = (allDayByKey[key] ?? []).sorted {
        $0.title.localizedStandardCompare($1.title) == .orderedAscending
      }
      return CalendarGridDay(
        date: date,
        dayKey: key,
        timedBlocks: blocks,
        allDayEvents: allDay,
        scheduledTasks: tasksByKey[key] ?? []
      )
    }
  }

  /// Chooses the hour row a scrollable time-axis view should reveal first.
  ///
  /// When today is among `days` and `nowMinute` is known, opens one hour before
  /// the current time so the now-line is in view on launch (matching first-party
  /// Calendar) — unless today has a timed event starting before that now-anchor,
  /// in which case it opens at that earliest event's hour so an early-morning
  /// appointment isn't scrolled off the top when the day is opened in the
  /// afternoon. Otherwise, if the visible days contain pre-workday timed content
  /// the anchor moves to midnight; failing that it opens at `fallbackHour`.
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
        .timedBlocks
        .map(\.startMin)
        .min()
        .map { $0 / 60 }
      if let todaysEarliestHour, todaysEarliestHour < nowAnchorHour {
        return todaysEarliestHour
      }
      return nowAnchorHour
    }
    let fallbackMinute = max(0, min(23, fallbackHour)) * 60
    let earliest =
      days
      .flatMap(\.timedBlocks)
      .map(\.startMin)
      .min()
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
