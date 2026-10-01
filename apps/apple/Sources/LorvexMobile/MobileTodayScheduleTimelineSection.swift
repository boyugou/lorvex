import LorvexCore
import SwiftUI

/// Today's calendar events and timed tasks in one reading order, for the
/// schedule pane beside Today on iPad and the schedule sheet on iPhone — the
/// same timeline the macOS pane draws. Each row is a time and a title, nothing
/// more: a task leads with its completion circle, and a finished task keeps its
/// place with its circle filled, so the day reads as it ran; a calendar event
/// leads with a thin bar in its calendar's color and carries no circle,
/// because it is not the user's to finish. The finished rows that open the day
/// collapse behind "N earlier" (``LorvexTodayTimeline/earlierFold(_:)``); a
/// row the clock has cleared fades its marker and quiets its title, so its
/// words stay legible. The time of a task whose time is running is drawn in
/// the accent color.
/// These are list rows: the caller's `List` owns the scrolling, insets, and
/// separators.
struct MobileTodayScheduleTimelineSection: View {
  @Bindable var store: MobileStore
  let items: [LorvexTodayTimelineItem]
  var openTask: (LorvexTask) -> Void = { _ in }
  var openEvent: (CalendarTimelineEvent) -> Void = { _ in }
  @State private var showsPast = false

  /// The rows on screen, in order: the folded rows only once unfolded.
  nonisolated static func visibleItems(
    of items: [LorvexTodayTimelineItem], showsPast: Bool
  ) -> [LorvexTodayTimelineItem] {
    guard !showsPast else { return items }
    let fold = LorvexTodayTimeline.earlierFold(items)
    return Array(items[..<fold.lowerBound] + items[fold.upperBound...])
  }

  var body: some View {
    let fold = LorvexTodayTimeline.earlierFold(items)
    rows(items[..<fold.lowerBound])
    if !fold.isEmpty {
      pastToggle(count: fold.count)
      if showsPast {
        rows(items[fold])
      }
    }
    rows(items[fold.upperBound...])
  }

  private func rows(_ slice: ArraySlice<LorvexTodayTimelineItem>) -> some View {
    ForEach(slice) { item in
      row(for: item)
    }
  }

  @ViewBuilder
  private func row(for item: LorvexTodayTimelineItem) -> some View {
    switch item.kind {
    case .task(let task):
      let isDone = task.status == .completed
      let isCurrent = !isDone && isRunning(item)
      let isBlocked = store.snapshot.blockedTaskIDs.contains(task.id)
      LorvexTimelineRow(
        time: item.timeLabel, title: task.title,
        duration: duration(item, task: task),
        isCurrent: isCurrent,
        isQuiet: isDone || isBlocked,
        isPast: item.isPast
      ) {
        Button {
          Task { await store.toggleTaskCompletion(task) }
        } label: {
          Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(
              isDone ? AnyShapeStyle(LorvexDesign.Palette.done) : AnyShapeStyle(.secondary))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(store.taskIsMutating(task.id))
        .accessibilityHidden(true)
      }
      .contentShape(Rectangle())
      .onTapGesture { openTask(task) }
      // One VoiceOver element per row, as on a task row: the value says what
      // the circle, the tint, and a quiet title show; the default action
      // opens the task; the circle's completion is a named action.
      .accessibilityValue(
        Self.accessibilityState(isDone: isDone, isCurrent: isCurrent, isBlocked: isBlocked))
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { openTask(task) }
      .accessibilityAction(named: Text(MobileTaskActionCopy.completionToggle(isDone: isDone))) {
        Task { await store.toggleTaskCompletion(task) }
      }
      .accessibilityIdentifier("today.schedule.task.\(task.id)")
    case .event(let event):
      LorvexTimelineRow(
        time: item.timeLabel.isEmpty ? allDayLabel : item.timeLabel, title: event.title,
        duration: duration(item, task: nil), isCurrent: false, isQuiet: true, isPast: item.isPast
      ) {
        Capsule()
          .fill(Color(lorvexHex: event.color) ?? LorvexDesign.Palette.neutral)
          .frame(width: 3, height: 16)
      }
      .contentShape(Rectangle())
      .onTapGesture { openEvent(event) }
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { openEvent(event) }
      .accessibilityIdentifier("today.schedule.event")
    case .now:
      LorvexTimelineNowMarker(
        minutes: item.startMinutes ?? 0,
        label: String(
          localized: "today.schedule.now.a11y", defaultValue: "Current time",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
  }

  /// A task row's state for VoiceOver, in the words the rest of the app uses:
  /// finished, running now, or waiting on another task. Empty for an open
  /// task outside its time.
  nonisolated static func accessibilityState(
    isDone: Bool, isCurrent: Bool, isBlocked: Bool
  ) -> String {
    guard !isDone else { return MobileTaskDisplayText.status(.completed) }
    var states: [String] = []
    if isCurrent {
      states.append(
        String(
          localized: "today.schedule.row_now.a11y", defaultValue: "Now", table: "Localizable",
          bundle: MobileL10n.bundle))
    }
    if isBlocked { states.append(MobileTaskDisplayText.blocked) }
    return states.joined(separator: ", ")
  }

  private func isRunning(_ item: LorvexTodayTimelineItem) -> Bool {
    guard let now = store.nowMinutesInProductDay, let start = item.startMinutes,
      let end = item.endMinutes
    else { return false }
    return (start..<end).contains(now)
  }

  private func duration(_ item: LorvexTodayTimelineItem, task: LorvexTask?) -> String? {
    let minutes: Int?
    if let start = item.startMinutes, let end = item.endMinutes, end > start {
      minutes = end - start
    } else {
      minutes = task?.estimatedMinutes
    }
    guard let minutes, minutes > 0 else { return nil }
    return MobileTodayCalmCopy.duration(minutes)
  }

  private var allDayLabel: String {
    String(
      localized: "calendar.all_day_short", defaultValue: "All day", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  private func pastToggle(count: Int) -> some View {
    Button {
      withAnimation(.snappy(duration: 0.18)) { showsPast.toggle() }
    } label: {
      HStack(spacing: LorvexDesign.Spacing.xs) {
        Image(systemName: "chevron.right")
          .imageScale(.small)
          .rotationEffect(.degrees(showsPast ? 90 : 0))
        Text(
          String(
            format: String(
              localized: "today.schedule.earlier_count", defaultValue: "%lld earlier",
              table: "Localizable", bundle: MobileL10n.bundle),
            count))
      }
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)
      .padding(.horizontal, LorvexTimelineMetrics.horizontalPadding)
      .padding(.vertical, LorvexDesign.Spacing.xs)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("today.schedule.earlier.toggle")
  }
}
