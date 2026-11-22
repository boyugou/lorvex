import LorvexCore
import SwiftUI

/// Calendar occurrences and planned tasks beside the journal. Times sit below
/// titles so both remain readable in the narrow context column.
struct DailyReviewAgenda: View {
  let day: LorvexAgendaDay
  let title: String
  let identifier: String
  let resolveSource: (CalendarTimelineEvent) async -> EventKitEventSource?
  let openCalendar: (CalendarTimelineEvent) -> Void
  var openTask: (String) -> Void
  @State private var expanded = false
  @State private var inspectedEventID: String?
  @State private var hoveredRow: String?
  private let previewCount = 3

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      LorvexPageLabel(title)
      let items = day.reviewItems
      ForEach(items.prefix(expanded ? items.count : previewCount)) { item in
        switch item.kind {
        case .event(let event):
          row(id: "event.\(event.id)", title: event.title,
            time: event.listTimeLabel(on: day.key, range: TodayCalmCopy.timeRange(start:end:)) ?? TodayCalmCopy.allDay,
            action: { inspectedEventID = event.id }
          ) {
            Capsule().fill(LorvexDesign.Palette.eventTint(event.color)).frame(width: 3)
          }
          .popover(isPresented: Binding(
            get: { inspectedEventID == event.id },
            set: { if !$0 && inspectedEventID == event.id { inspectedEventID = nil } }
          )) {
            CalendarEventInspector(
              event: event,
              actions: .preview { copy in
                inspectedEventID = nil
                openCalendar(copy)
              },
              close: { inspectedEventID = nil },
              resolveSource: resolveSource,
              fixedWidth: 340)
              .onExitCommand { inspectedEventID = nil }
          }
          .onDisappear { if inspectedEventID == event.id { inspectedEventID = nil } }
        case .task(let task):
          row(id: task.id, title: task.title,
            time: task.time(on: day.key).map { TodayCalmCopy.timeRange(start: $0.lowerBound, end: $0.upperBound) },
            action: { openTask(task.id) }
          ) {
            Image(systemName: "list.bullet").foregroundStyle(.secondary)
          }
        case .now: EmptyView()
        }
      }
      if items.count > previewCount {
        Button(expanded ? TodayCalmCopy.briefingLess : ReviewCalmCopy.moreCount(items.count - previewCount)) {
          lorvexAnimated(.snappy) { expanded.toggle() }
        }
        .buttonStyle(.link)
        .font(LorvexDesign.Typography.secondaryText)
      }
      if items.isEmpty {
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
