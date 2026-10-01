import SwiftUI

/// A week review's look at the seven days after today, shown while the review
/// is of the current week: each day that has something on it, with its
/// events (a bar in the calendar's color, the title, the time) and then its
/// scheduled tasks (a small dot, the title, its time), each task opening when
/// tapped. Each item shows only its start time, which is what a look across a
/// week needs, so the titles keep the row's width. A day shows its first
/// ``itemsPerDay`` items and counts the rest. An empty week reads one quiet
/// line saying so.
///
/// The day sits in a column beside its items, or above them from `.xxLarge`
/// up (``SwiftUI/DynamicTypeSize/stacksTimeColumn``). The section's
/// identifier names it; a day appends its key, a task row the task id, and
/// the empty line "empty".
public struct LorvexReviewWeekAhead: View {
  public struct Words {
    public var label: String
    public var emptyLine: String
    public var allDay: String
    /// "Mon, Oct 5" for a day key.
    public var dayLabel: (String) -> String
    /// "2 more": a day's items past the listed ones.
    public var moreLine: (Int) -> String
    /// A start and optional end in minutes after midnight ("9:00 – 9:30");
    /// the section passes only a start ("9:00 AM").
    public var timeRange: (Int, Int?) -> String

    public init(
      label: String, emptyLine: String, allDay: String, dayLabel: @escaping (String) -> String,
      moreLine: @escaping (Int) -> String, timeRange: @escaping (Int, Int?) -> String
    ) {
      self.label = label
      self.emptyLine = emptyLine
      self.allDay = allDay
      self.dayLabel = dayLabel
      self.moreLine = moreLine
      self.timeRange = timeRange
    }
  }

  /// How many of a day's events and tasks are listed before the rest are
  /// counted.
  public static let itemsPerDay = 4

  private let days: [LorvexAgendaDay]
  private let words: Words
  private let identifier: String
  private let openTask: (String) -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// ``LorvexDesign/TextColumn/reviewDay`` scaled with the text.
  @ScaledMetric(relativeTo: .subheadline) private var dayColumnWidth = LorvexDesign.TextColumn.reviewDay
  @State private var hoveredTaskID: String?

  public init(
    days: [LorvexAgendaDay], words: Words, identifier: String, openTask: @escaping (String) -> Void
  ) {
    self.days = days
    self.words = words
    self.identifier = identifier
    self.openTask = openTask
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      LorvexPageLabel(words.label)
      if days.isEmpty {
        Text(words.emptyLine)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("\(identifier).empty")
      } else {
        ForEach(days) { day in
          dayRow(day)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(identifier)
  }

  private enum Item: Identifiable {
    case event(CalendarTimelineEvent)
    case task(LorvexTask)

    var id: String {
      switch self {
      case .event(let event): "event.\(event.id)"
      case .task(let task): "task.\(task.id)"
      }
    }
  }

  private func items(_ day: LorvexAgendaDay) -> [Item] {
    day.events.map(Item.event) + day.tasks.map(Item.task)
  }

  @ViewBuilder
  private func dayRow(_ day: LorvexAgendaDay) -> some View {
    let all = items(day)
    let shown = all.prefix(Self.itemsPerDay)
    let content = VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(shown)) { item in
        switch item {
        case .event(let event): eventRow(event)
        case .task(let task): taskRow(task, dayKey: day.key)
        }
      }
      if all.count > shown.count {
        Text(words.moreLine(all.count - shown.count))
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .padding(.vertical, LorvexDesign.Spacing.xxs)
      }
    }
    Group {
      if dynamicTypeSize.stacksTimeColumn {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
          dayLabel(day.key)
          content
        }
      } else {
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          dayLabel(day.key)
            .frame(minWidth: dayColumnWidth, alignment: .leading)
          content
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.xxs)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("\(identifier).\(day.key)")
  }

  private func dayLabel(_ key: String) -> some View {
    Text(words.dayLabel(key))
      .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
      .foregroundStyle(.secondary)
      // Level with the first item's title, which sits a row's padding down.
      .padding(.vertical, LorvexDesign.Spacing.xxs)
  }

  private func eventRow(_ event: CalendarTimelineEvent) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      marker {
        Capsule()
          .fill(Color(lorvexHex: event.color) ?? LorvexDesign.Palette.neutral)
          .frame(width: 3, height: 14)
      }
      Text(event.title)
        .font(LorvexDesign.Typography.primaryText)
        .lineLimitUnlessAccessibilitySize(2)
      Spacer(minLength: LorvexDesign.Spacing.s)
      timeText(eventTime(event))
    }
    .padding(.vertical, LorvexDesign.Spacing.xxs)
    .accessibilityElement(children: .combine)
  }

  private func taskRow(_ task: LorvexTask, dayKey: String) -> some View {
    Button { openTask(task.id) } label: {
      HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
        marker {
          Circle()
            .strokeBorder(.secondary, lineWidth: 1.5)
            .frame(width: 7, height: 7)
        }
        Text(task.title)
          .font(LorvexDesign.Typography.primaryText)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
          .lineLimitUnlessAccessibilitySize(2)
        Spacer(minLength: LorvexDesign.Spacing.s)
        if let time = task.time(on: dayKey) {
          timeText(words.timeRange(time.lowerBound, nil))
        }
      }
      .padding(.vertical, LorvexDesign.Spacing.xxs)
      // The fill reaches past the row on both sides, and the negative padding
      // gives that reach back, so the row stays aligned with the day's column.
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
      // The title wraps; the time keeps its whole width.
      .fixedSize()
  }

  private func eventTime(_ event: CalendarTimelineEvent) -> String {
    guard !event.allDay, let start = CalendarGridModel.parseMinutes(event.startTime) else {
      return words.allDay
    }
    return words.timeRange(start, nil)
  }
}
