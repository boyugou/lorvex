import LorvexCore
import SwiftUI

/// An event under a day of the agenda: a glyph (a sun for an all-day event or
/// a day a longer event fills, which both read "all day"), its title, and its
/// time and place, with a repeat mark when it repeats. The
/// title and the time each keep to two lines, and show whole at the
/// accessibility text sizes. An event the clock has cleared steps back
/// without losing legibility: its glyph fades and its title takes the
/// secondary style, as a past row of the Today schedule does.
struct MobileCalendarAgendaRow: View {
  let event: CalendarTimelineEvent
  /// The row's day as `yyyy-MM-dd`, to read the part of the event it holds.
  let dayKey: String
  var isPast = false

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      // As wide as a task row's completion circle, so event and task titles
      // share one leading edge.
      Image(systemName: event.allDay || event.dayPart(on: dayKey) == .middleDay ? "sun.max" : "calendar")
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .opacity(isPast ? LorvexDesign.Palette.pastMarkOpacity : 1)
        .mobileTaskCircleFrame(isSquare: false)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        Text(userContent: event.title)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .foregroundStyle(isPast ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
          .lineLimitUnlessAccessibilitySize(2)
        Text(subtitle)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .lineLimitUnlessAccessibilitySize(2)
      }

      Spacer(minLength: LorvexDesign.Spacing.s)

      if event.isRecurring || event.supportsScopedMutation {
        Image(systemName: "repeat")
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .accessibilityLabel(
            String(
              localized: "calendar.repeating_event.a11y", defaultValue: "Repeating event",
              table: "Localizable", bundle: MobileL10n.bundle))
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.s)
    // The whole row is the button's tap area: a plain button takes touches only
    // on its label's drawn content and a short way around it, so the empty
    // middle and right of a row with a short title were dead.
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("mobileCalendar.agendaRow.\(event.id)")
  }

  /// The time, then the place, joined by a dot. The time stays whole except
  /// after a span's dash; a long place wraps between its words.
  private var subtitle: String {
    var facts = [lorvexUnbreakable(timeLabel)]
    if let location = event.location, !location.isEmpty { facts.append(location) }
    return lorvexDotJoined(facts)
  }

  /// The event's time on the row's day, on the user's 12- or 24-hour clock:
  /// a span when it has an end ("9:00 – 9:30 AM", naming the day period once),
  /// the way the task rows beside it read theirs, and for one day of an event
  /// that runs past midnight its start on the first day and "Until 1:30 AM" on
  /// the last; "all day" for an all-day event or a day a longer event fills,
  /// and "time unset" for a timed event without a clock time.
  private var timeLabel: String {
    if !event.allDay, event.startTime == nil {
      return String(
        localized: "calendar.time_unset", defaultValue: "time unset", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
    return event.listTimeLabel(on: dayKey, range: MobileTodayCalmCopy.timeRange(start:end:))
      ?? String(
        localized: "calendar.all_day", defaultValue: "all day", table: "Localizable",
        bundle: MobileL10n.bundle)
  }
}

/// A task under a day of the agenda: its completion circle, then its title and
/// the facts the day gives it (``subtitle(for:dayKey:)``). Like an event row's,
/// the title and the facts each keep to two lines, and show whole at the
/// accessibility text sizes. The circle completes the task and the rest of
/// the row opens it; the row swipes and long-presses with the shared task
/// actions, without Start while the task is blocked, and drags onto a
/// calendar day to plan the task there. A done task keeps its place with its
/// title struck through, as on every task row.
struct MobileCalendarAgendaTaskRow: View {
  let task: LorvexTask
  /// The row's day as `yyyy-MM-dd`, to read the task's time on it and to tell
  /// a due date from a planned one.
  let dayKey: String
  let isMutating: Bool
  /// The task waits on an unfinished task: the facts end with "Blocked" and
  /// the row's actions offer no Start.
  var isBlocked = false
  let actions: MobileTaskRowActions
  let open: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      MobileTaskCompletionCircle(task: task, isMutating: isMutating, complete: actions.complete)

      Button(action: open) {
        HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
            Text(userContent: task.title)
              .font(LorvexDesign.Typography.primaryEmphasis)
              .foregroundStyle(isDormant ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
              .strikethrough(task.status.isResolved, color: .secondary)
              .lineLimitUnlessAccessibilitySize(2)
            if let subtitle = Self.subtitle(for: task, dayKey: dayKey, isBlocked: isBlocked) {
              Text(subtitle)
                .font(LorvexDesign.Typography.secondaryText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimitUnlessAccessibilitySize(2)
            }
          }
          Spacer(minLength: 0)
        }
        // Level with the completion circle, which insets itself by `Spacing.xs`.
        .padding(.top, LorvexDesign.Spacing.xs)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("mobileCalendar.agendaTaskRow.\(task.id)")
    }
    // Together with the inset above, the circle and the title start
    // `Spacing.s` from the top, where an event row's title starts.
    .padding(.top, LorvexDesign.Spacing.xs)
    .padding(.bottom, LorvexDesign.Spacing.s)
    // Dropped on a day of the calendar beside or above the agenda, the task
    // is planned on that day.
    .draggable(LorvexTaskRef(id: task.id, title: task.title))
    .lorvexRowHoverEffect()
    .taskRowActions(
      task: task, actions: actions, isMutating: isMutating, isBatchSelecting: false,
      isHeldUp: isBlocked)
  }

  private var isDormant: Bool { task.status.isResolved || task.status == .someday }

  /// The line under a task's title on the day `dayKey` (`yyyy-MM-dd`): the
  /// task's time that day when it has one, else its estimate, then "Due" when
  /// the day is its due date, then "Blocked" when `isBlocked`, joined by a
  /// dot; nil when none of them applies. Each fact stays whole except after a
  /// span's dash, so the line breaks only there or after a dot.
  nonisolated static func subtitle(
    for task: LorvexTask, dayKey: String, isBlocked: Bool = false
  ) -> String? {
    var facts: [String] = []
    if let time = task.time(on: dayKey) {
      facts.append(lorvexClockRangeLabel(startMinutes: time.lowerBound, endMinutes: time.upperBound))
    } else if let minutes = task.estimatedMinutes, minutes > 0 {
      facts.append(LorvexDurationFormat.minutes(minutes))
    }
    if let due = task.dueDate, LorvexDateFormatters.ymdUTC.string(from: due) == dayKey {
      facts.append(
        String(
          localized: "calendar.agenda.task.due", defaultValue: "Due", table: "Localizable",
          bundle: MobileL10n.bundle))
    }
    if isBlocked { facts.append(MobileTaskDisplayText.blocked) }
    return facts.isEmpty ? nil : lorvexDotJoined(facts.map(lorvexUnbreakable))
  }
}
