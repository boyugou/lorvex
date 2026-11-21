import Foundation

/// An action on Today's lead task. A future time stays in the schedule. Only
/// work the person started or planned for the current time comes to the top.
public struct TodayWorkCue: Equatable, Sendable {
  public enum Action: Equatable, Sendable {
    case start
    case resume
    case reviewConflict(event: String)
  }

  public struct UpcomingEvent: Equatable, Sendable {
    public let title: String
    public let minutesAway: Int
  }

  public let taskID: LorvexTask.ID
  public let action: Action
  public let upcoming: UpcomingEvent?

  public var bringsTaskToTop: Bool {
    switch action {
    case .start, .resume: true
    case .reviewConflict: false
    }
  }

  public static func resolve(
    lead: LorvexCalmToday.Item?, blocked: Set<LorvexTask.ID>,
    events: [CalendarTimelineEvent], day: String, nowMinutes: Int?, now: Date? = nil
  ) -> Self? {
    guard let lead, let nowMinutes, lead.task.status.isActionable else { return nil }
    let clock = CalendarAgendaClock(day: day, events: events)
    // Known instants distinguish the two readings of an autumn clock. A
    // caller supplying only a civil clock uses its first reading.
    let position = clock.dayStart != nil ? now.map(clock.position(instant:)) : nil
    let current = position ?? clock.position(minute: nowMinutes)
    let block = lead.time.flatMap { time -> Range<Double>? in
      let start = clock.position(minute: time.lowerBound)
      let end = clock.position(minute: time.upperBound)
      return start < end ? start..<end : nil
    }
    let isStarted = lead.task.status == .inProgress
    let isCurrent = block?.contains(current) == true
    let isFuture = block.map { $0.lowerBound > current } ?? false
    guard isStarted || isCurrent || isFuture else { return nil }

    var occupied = false
    var next: (start: Double, title: String)?
    var conflict: (start: Double, title: String)?
    for event in events where !event.allDay && event.occurs(on: day) {
      guard let interval = clock.eventInterval(event, on: day) else { continue }
      let (start, end) = interval
      if start > current, next.map({ start < $0.start }) ?? true {
        next = (start, event.title)
      }
      guard end > current, end > start else { continue }
      if start <= current { occupied = true }
      if let block, max(current, block.lowerBound, start) < min(block.upperBound, end),
        conflict.map({ start < $0.start }) ?? true {
        conflict = (start, event.title)
      }
    }

    if let conflict, occupied || (!isStarted && isFuture) {
      return Self(taskID: lead.id, action: .reviewConflict(event: conflict.title), upcoming: nil)
    }
    guard !occupied, isStarted || isCurrent, isStarted || !blocked.contains(lead.id) else { return nil }
    let upcoming = next.map { UpcomingEvent(title: $0.title, minutesAway: Int(ceil($0.start - current))) }
    return Self(taskID: lead.id, action: isStarted ? .resume : .start, upcoming: upcoming)
  }
}

extension CalendarAgendaClock {
  /// Elapsed coordinates on the agenda. A start-only event counts as the next
  /// appointment, but supplies no end from which to infer an occupied interval.
  fileprivate func eventInterval(_ event: CalendarTimelineEvent, on day: String) -> (Double, Double)? {
    if let projection = event.projection, dayStart != nil {
      let start = position(instant: projection.start)
      return (start, projection.end.map(position(instant:)) ?? start)
    }
    if event.dayPart(on: day) == .middleDay {
      return (position(minute: 0), position(minute: 1440))
    }
    guard let span = event.clockSpan(on: day) else { return nil }
    let start = position(minute: span.start)
    return (start, span.end.map(position(minute:)) ?? start)
  }
}
