import SwiftUI

/// A day review's look at the next day, shown while the review is of today:
/// tomorrow's events (a bar in the calendar's color, the title, the time) and
/// then its scheduled tasks (a small dot, the title, its time), each task
/// opening when tapped. An empty tomorrow reads one quiet line saying so, which
/// is itself the answer the section exists to give. Each row is a
/// ``LorvexReviewAheadRow``.
///
/// The section's identifier names it; event rows append "event", task rows
/// append the task id, and the empty line appends "empty".
public struct LorvexReviewTomorrow: View {
  private let label: String
  private let day: LorvexAgendaDay?
  private let emptyLine: String
  private let allDay: String
  private let timeRange: (Int, Int?) -> String
  private let identifier: String
  private let openTask: (String) -> Void

  @State private var hoveredTaskID: String?

  /// `timeRange` words a start and optional end in minutes after midnight
  /// ("9:00 – 9:30") the way the platform's Today does.
  public init(
    label: String, day: LorvexAgendaDay?, emptyLine: String, allDay: String,
    timeRange: @escaping (Int, Int?) -> String, identifier: String,
    openTask: @escaping (String) -> Void
  ) {
    self.label = label
    self.day = day
    self.emptyLine = emptyLine
    self.allDay = allDay
    self.timeRange = timeRange
    self.identifier = identifier
    self.openTask = openTask
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      LorvexPageLabel(label)
      if let day, !day.events.isEmpty || !day.tasks.isEmpty {
        ForEach(day.events) { eventRow($0, dayKey: day.key) }
        ForEach(day.tasks) { taskRow($0, dayKey: day.key) }
      } else {
        Text(emptyLine)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("\(identifier).empty")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(identifier)
  }

  private func eventRow(_ event: CalendarTimelineEvent, dayKey: String) -> some View {
    LorvexReviewAheadRow(
      mark: .event(Color(lorvexHex: event.color) ?? LorvexDesign.Palette.neutral),
      title: event.title, time: eventTime(event, dayKey: dayKey)
    )
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("\(identifier).event")
  }

  private func taskRow(_ task: LorvexTask, dayKey: String) -> some View {
    Button { openTask(task.id) } label: {
      LorvexReviewAheadRow(
        mark: .task, title: task.title,
        time: task.time(on: dayKey).map { timeRange($0.lowerBound, $0.upperBound) }
      )
      // The fill reaches past the row on both sides, and the negative padding
      // gives that reach back, so the row stays aligned with the label above.
      .padding(.horizontal, LorvexDesign.Spacing.s)
      .background {
        if hoveredTaskID == task.id {
          RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
            .fill(LorvexDesign.Palette.hoverFill)
        }
      }
      .contentShape(Rectangle())
      .padding(.horizontal, -LorvexDesign.Spacing.s)
    }
    .buttonStyle(.plain)
    #if os(macOS) || os(iOS)
      .onHover { inside in
        if inside {
          hoveredTaskID = task.id
        } else if hoveredTaskID == task.id {
          hoveredTaskID = nil
        }
      }
    #endif
    .accessibilityIdentifier("\(identifier).\(task.id)")
  }

  /// An event's time on the day: its range, the all-day word, or for one day
  /// of an event that runs past midnight its start on the first day and
  /// "Until 1:30 AM" on the last.
  private func eventTime(_ event: CalendarTimelineEvent, dayKey: String) -> String {
    event.listTimeLabel(on: dayKey, range: timeRange) ?? allDay
  }
}
