import SwiftUI

/// Suggested times drawn in the day timeline's columns, so a suggestion lines
/// up with the day beneath it: each row is a start time, a marker, a title, and
/// a length (``LorvexTimelineRow``). The placed tasks and the calendar events
/// the suggestion worked around interleave by start. A task leads with a
/// dashed circle in the accent color: its time is suggested, not saved, so
/// there is nothing to complete yet. An event leads with a thin bar in its
/// calendar's color, found among `dayRows`, the day's timeline. The tasks the
/// suggestion could not place follow, with `wontFitLabel` in the time column.
///
/// The caller supplies every word, so each app keeps its own string table:
/// `busyLabel` names an event the suggestion may only describe as busy time,
/// and `durationLabel` renders a length in minutes. The body is a flat
/// sequence of rows, so a `List` gives each one its own row.
public struct LorvexProposedScheduleRows: View {
  public var proposal: DayTimesProposal
  public var dayRows: [LorvexTodayTimelineItem]
  public var wontFitLabel: String
  public var busyLabel: String
  public var durationLabel: (Int) -> String

  public init(
    proposal: DayTimesProposal,
    dayRows: [LorvexTodayTimelineItem],
    wontFitLabel: String,
    busyLabel: String,
    durationLabel: @escaping (Int) -> String
  ) {
    self.proposal = proposal
    self.dayRows = dayRows
    self.wontFitLabel = wontFitLabel
    self.busyLabel = busyLabel
    self.durationLabel = durationLabel
  }

  /// One drawn row of a suggestion, in start order.
  public enum Row: Identifiable, Equatable, Sendable {
    case task(DayTimesProposal.Placement)
    case event(DayTimesProposal.Event, index: Int)

    public var id: String {
      switch self {
      case .task(let placement): "task:\(placement.id)"
      case .event(_, let index): "event:\(index)"
      }
    }

    public var time: Range<Int> {
      switch self {
      case .task(let placement): placement.time
      case .event(let event, _): event.time
      }
    }
  }

  public var body: some View {
    ForEach(Self.rows(of: proposal)) { row in
      switch row {
      case .task(let placement):
        LorvexTimelineRow(
          time: lorvexClockTimeLabel(minutes: placement.time.lowerBound),
          title: placement.task.title,
          duration: durationLabel(placement.time.count),
          isCurrent: false, isQuiet: false
        ) {
          Image(systemName: "circle.dashed")
            .foregroundStyle(.tint)
        }
        .accessibilityIdentifier("today.suggestion.task")
      case .event(let event, _):
        LorvexTimelineRow(
          time: lorvexClockTimeLabel(minutes: event.time.lowerBound),
          title: event.title.flatMap { $0.isEmpty ? nil : $0 } ?? busyLabel,
          duration: durationLabel(event.time.count),
          isCurrent: false, isQuiet: true
        ) {
          Capsule()
            .fill(
              Color(lorvexHex: Self.eventColorHex(for: event, among: dayRows))
                ?? LorvexDesign.Palette.neutral
            )
            .frame(width: 3, height: 16)
        }
      }
    }
    ForEach(proposal.unscheduled) { task in
      LorvexTimelineRow(
        time: wontFitLabel, title: task.title,
        duration: task.estimatedMinutes.flatMap { $0 > 0 ? durationLabel($0) : nil },
        isCurrent: false, isQuiet: false
      ) {
        Image(systemName: "circle.dashed")
          .foregroundStyle(.tertiary)
      }
      .accessibilityIdentifier("today.suggestion.wontFit")
    }
  }

  // The helpers below are pure, so they carry no main-actor isolation and
  // callers on any executor can use them.

  /// The placed tasks and the events, ascending by start; at the same start an
  /// event comes first, as on the day's timeline.
  public nonisolated static func rows(of proposal: DayTimesProposal) -> [Row] {
    let events = proposal.events.enumerated().map { Row.event($1, index: $0) }
    let tasks = proposal.placements.map(Row.task)
    return (events + tasks).enumerated()
      .sorted { lhs, rhs in
        lhs.element.time.lowerBound != rhs.element.time.lowerBound
          ? lhs.element.time.lowerBound < rhs.element.time.lowerBound : lhs.offset < rhs.offset
      }
      .map(\.element)
  }

  /// The stored color of the calendar event a suggestion row stands for. An
  /// event with an id matches the timeline event with that source address; a
  /// device-calendar event carries none and matches by title and start. `nil`
  /// when the day's timeline does not show the event.
  public nonisolated static func eventColorHex(
    for event: DayTimesProposal.Event, among dayRows: [LorvexTodayTimelineItem]
  ) -> String? {
    for row in dayRows {
      guard case .event(let timelineEvent) = row.kind else { continue }
      let isSameEvent =
        event.eventID.map { $0 == timelineEvent.eventID }
        ?? (timelineEvent.title == event.title && row.startMinutes == event.time.lowerBound)
      if isSameEvent { return timelineEvent.color }
    }
    return nil
  }
}
