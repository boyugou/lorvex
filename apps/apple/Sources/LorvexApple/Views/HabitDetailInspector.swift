import LorvexCore
import SwiftUI

/// The Habits workspace's trailing inspector, built like the task inspector
/// (``TaskDetailView``) from the shared inspector kit, so a habit reads and
/// edits the way a task does: the header with the check-in ring, the name,
/// and the encouragement (``HabitDetailHeader``); the period's standing and
/// the overflow menu (``HabitDetailActions``); the fields
/// (``HabitDetailProperties``); then the Progress, History, and By Weekday
/// panels. By Weekday shows only for a habit planned on more than one weekday.
///
/// Every edit happens in place: the name and the encouragement in their
/// fields, the rhythm, reminders, and goal in their fields' popovers, and the
/// icon and color in a popover on the ring, which the overflow menu opens.
///
/// The habit's period progress comes from its stats, which the catalog loads
/// for its cards, so the ring and the standing are right before the
/// inspector's own detail (history and reminders) arrives; the detail's
/// fresher stats take over once it loads.
struct HabitDetailInspector: View {
  @Bindable var store: AppStore
  let habitID: LorvexHabit.ID

  /// Whether the ring's icon and color popover is open; the header shows it
  /// and the overflow menu opens it.
  @State private var isChoosingAppearance = false

  private var habit: LorvexHabit? {
    store.orderedHabits.first { $0.id == habitID }
  }

  var body: some View {
    Group {
      if let habit {
        content(habit: habit)
      } else {
        DetachedWindowPlaceholder(
          systemImage: "repeat.circle",
          title: String(
            localized: "habit_detail.placeholder.title", defaultValue: "Habit Not Found",
            table: "Localizable",
            bundle: LorvexL10n.bundle)
        )
      }
    }
    .task(id: habitID) { await store.loadHabitDetail(id: habitID) }
    .onChange(of: habitID) { _, _ in isChoosingAppearance = false }
  }

  private func content(habit: LorvexHabit) -> some View {
    let detail = store.habitDetail(for: habit.id)
    let stats = detail?.stats ?? store.habitStats(for: habit.id)
    let progress = HabitPeriodProgress.current(
      habit: habit, recentCompletions: stats?.recentCompletions ?? [],
      recentSkips: stats?.recentSkips ?? [], timeZone: store.logicalTimeZone)
    let rhythm = detail.flatMap {
      HabitWeekdayRhythm.make(
        habit: habit, completions: $0.completions.completions, today: Date(),
        calendar: Self.gregorian(in: store.logicalTimeZone))
    }
    return InspectorScrollView {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        HabitDetailHeader(
          store: store, habit: habit, progress: progress,
          isChoosingAppearance: $isChoosingAppearance)
        HabitDetailActions(
          store: store, habit: habit, progress: progress,
          isChoosingAppearance: $isChoosingAppearance)
        HabitDetailProperties(
          store: store, habit: habit, reminderPolicies: detail?.reminderPolicies)
        HabitProgressPanel(habit: habit, stats: stats)
        HabitHistoryPanel(habit: habit, detail: detail, timeZone: store.logicalTimeZone)
        if let rhythm {
          HabitWeekdayPanel(habit: habit, rhythm: rhythm)
        }
      }
    }
    .frame(minWidth: 0, maxWidth: .infinity)
    .background(.quaternary.opacity(0.035))
    // Re-identify the content per habit so the reused inspector rebuilds on a
    // switch: the header's fields, the reminder rows, and the history cache
    // hold per-habit state that must not carry over to the next habit.
    .id(habit.id)
    // No `navigationTitle`: as the workspace's trailing inspector it would
    // replace the window title (the workspace) with the habit's name.
  }

  /// The Gregorian calendar in `timeZone`, the product time zone the
  /// history's `yyyy-MM-dd` dates are written in, which reads them whatever
  /// calendar the person uses.
  private static func gregorian(in timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }
}
