import Foundation
import LorvexCore

/// Holds runtime state for the habits domain: the loaded habit catalog, draft
/// fields for creating a new habit, and a per-habit detail cache (completion
/// history + stats) keyed by habit ID for expanded rows.
struct AppStoreHabitsStorage {
  var habits: HabitCatalogSnapshot?
  /// Archived habits, loaded on demand for the restore surface. Empty until the
  /// habits workspace appears (kept separate from the active `habits` catalog).
  var archivedHabits: [LorvexHabit] = []
  var draftHabitName = ""
  var draftHabitCue = ""
  var draftHabitTargetCountText = "1"
  /// Optional milestone goal ("celebrate at N"), as raw field text. Empty means
  /// no personal goal; a positive integer sets one. Cleared on reset and seeded
  /// from a habit's `milestoneTarget` on edit.
  var draftHabitMilestoneTargetText = ""
  /// Cadence mode for the create/edit editor. Assembled into a typed
  /// ``HabitCadenceInput`` on save by ``AppStore``.
  var draftHabitCadenceMode: HabitCadenceMode = .daily
  /// Selected weekdays for the `weekly` mode, as ``WeekDay`` raw values
  /// (0 = Mon … 6 = Sun). Kept non-empty by the picker.
  var draftHabitWeekdays: Set<Int> = [0, 2, 4]
  /// Target count for the `timesPerWeek` mode (1…7).
  var draftHabitTimesPerWeek = 3
  /// Day of the month (1…31) reminders fire on for the `monthly` mode.
  var draftHabitDayOfMonth = 1
  /// SF Symbol name; nil uses the default glyph.
  var draftHabitIcon: String?
  /// `#RRGGBB` hex; nil uses the per-habit auto hue.
  var draftHabitColor: String?
  /// Reminder times ("HH:mm") to arm when the habit is created. Only the create
  /// flow reads these; each becomes an enabled reminder policy on the new habit.
  /// Post-creation reminder edits go through the detail inspector's live editor,
  /// not this draft.
  var draftHabitReminderTimes: [String] = []
  var detailsByHabitID: [LorvexHabit.ID: AppStore.HabitDetail] = [:]
  /// Real per-habit stats (streak, rate, recent completions) for the cards —
  /// loaded from the core so cards never show estimated/fabricated values.
  var habitStatsByID: [LorvexHabit.ID: HabitStats] = [:]

  mutating func reset() {
    habits = nil
    archivedHabits = []
    draftHabitName = ""
    draftHabitCue = ""
    draftHabitTargetCountText = "1"
    draftHabitMilestoneTargetText = ""
    draftHabitCadenceMode = .daily
    draftHabitWeekdays = [0, 2, 4]
    draftHabitTimesPerWeek = 3
    draftHabitDayOfMonth = 1
    draftHabitIcon = nil
    draftHabitColor = nil
    draftHabitReminderTimes = []
    detailsByHabitID = [:]
    habitStatsByID = [:]
  }
}
