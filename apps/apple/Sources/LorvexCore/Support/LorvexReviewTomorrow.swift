import SwiftUI

/// A day review's look at the next day, shown while the review is of today:
/// tomorrow's events (a bar in the calendar's color, the title, the time) and
/// then its scheduled tasks (a small dot, the title, its time), each task
/// opening when tapped. An empty tomorrow reads one quiet line saying so, which
/// is itself the answer the section exists to give.
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
        ForEach(day.events) { eventRow($0) }
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

  private func eventRow(_ event: CalendarTimelineEvent) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      marker {
        Capsule()
          .fill(Color(lorvexHex: event.color) ?? LorvexDesign.Palette.neutral)
          .frame(width: 3, height: 14)
      }
      Text(userContent: event.title)
        .font(LorvexDesign.Typography.primaryText)
        .lineLimit(2)
      Spacer(minLength: LorvexDesign.Spacing.s)
      timeText(eventTime(event))
    }
    .padding(.vertical, LorvexDesign.Spacing.xxs)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("\(identifier).event")
  }

  private func taskRow(_ task: LorvexTask, dayKey: String) -> some View {
    Button { openTask(task.id) } label: {
      HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
        marker {
          Circle()
            .strokeBorder(.secondary, lineWidth: 1.5)
            .frame(width: 7, height: 7)
        }
        Text(userContent: task.title)
          .font(LorvexDesign.Typography.primaryText)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
          .lineLimit(2)
        Spacer(minLength: LorvexDesign.Spacing.s)
        if let time = task.time(on: dayKey) {
          timeText(timeRange(time.lowerBound, time.upperBound))
        }
      }
      .padding(.vertical, LorvexDesign.Spacing.xxs)
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

  /// A row's leading mark, centered in a fixed column on the title's first
  /// line so event bars and task dots stack in one line.
  private func marker(@ViewBuilder _ content: () -> some View) -> some View {
    content()
      .frame(width: 14)
      .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
      .accessibilityHidden(true)
  }

  private func timeText(_ text: String) -> some View {
    Text(text)
      .font(LorvexDesign.Typography.secondaryText)
      .foregroundStyle(.secondary)
      .monospacedDigit()
      .lineLimit(1)
  }

  private func eventTime(_ event: CalendarTimelineEvent) -> String {
    guard !event.allDay, let start = CalendarGridModel.parseMinutes(event.startTime) else {
      return allDay
    }
    return timeRange(start, CalendarGridModel.parseMinutes(event.endTime))
  }
}
