import LorvexCore
import SwiftUI

/// Calendar occurrences and planned tasks beside the journal. Times sit below
/// titles so both remain readable in the narrow context column.
struct DailyReviewAgenda: View {
  let day: LorvexAgendaDay
  let title: String
  let identifier: String
  var openEvent: (CalendarTimelineEvent) -> Void
  var openTask: (String) -> Void
  @State private var expanded = false
  @State private var hoveredRow: String?
  private let previewCount = 3

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      LorvexPageLabel(title)
      ForEach(day.events.prefix(expanded ? day.events.count : previewCount)) { event in
        row(id: "event.\(event.id)", title: event.title,
          time: event.listTimeLabel(on: day.key, range: TodayCalmCopy.timeRange(start:end:)) ?? TodayCalmCopy.allDay,
          action: { openEvent(event) }
        ) {
          Capsule().fill(LorvexDesign.Palette.eventTint(event.color)).frame(width: 3)
        }
      }
      if day.events.count > previewCount {
        Button(expanded ? TodayCalmCopy.briefingLess : ReviewCalmCopy.moreCount(day.events.count - previewCount)) {
          lorvexAnimated(.snappy) { expanded.toggle() }
        }
        .buttonStyle(.link)
        .font(LorvexDesign.Typography.secondaryText)
      }
      ForEach(day.tasks) { task in
        row(id: task.id, title: task.title,
          time: task.time(on: day.key).map { TodayCalmCopy.timeRange(start: $0.lowerBound, end: $0.upperBound) },
          action: { openTask(task.id) }
        ) {
          Image(systemName: "list.bullet").foregroundStyle(.secondary)
        }
      }
      if day.events.isEmpty && day.tasks.isEmpty {
        Text(ReviewCalmCopy.tomorrowEmpty)
          .font(LorvexDesign.Typography.secondaryText).foregroundStyle(.secondary)
          .accessibilityIdentifier("\(identifier).empty")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(identifier)
  }

  private func row(
    id: String, title: String, time: String?, action: @escaping () -> Void,
    @ViewBuilder mark: () -> some View
  ) -> some View {
    Button(action: action) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        mark().accessibilityHidden(true)
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
          Text(userContent: title)
            .font(LorvexDesign.Typography.primaryText)
            .lineLimitUnlessAccessibilitySize(2)
          if let time {
            Text(time).font(LorvexDesign.Typography.secondaryText)
              .foregroundStyle(.secondary).monospacedDigit()
          }
        }
        Spacer(minLength: 0)
      }
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, LorvexDesign.Spacing.xs)
      .background(hoveredRow == id ? LorvexDesign.Palette.hoverFill : .clear,
        in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
      .contentShape(Rectangle())
      .padding(.horizontal, -LorvexDesign.Spacing.xs)
    }
    .buttonStyle(.plain)
    .onHover { inside in
      if inside { hoveredRow = id }
      else if hoveredRow == id { hoveredRow = nil }
    }
    .help(TodayCalmCopy.openDetails)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("\(identifier).\(id)")
  }
}
