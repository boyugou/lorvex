import LorvexCore

extension AppStore {
  var habits: HabitCatalogSnapshot? {
    get { habitsStorage.habits }
    set { habitsStorage.habits = newValue }
  }

  var draftHabitName: String {
    get { habitsStorage.draftHabitName }
    set { habitsStorage.draftHabitName = newValue }
  }

  var draftHabitCue: String {
    get { habitsStorage.draftHabitCue }
    set { habitsStorage.draftHabitCue = newValue }
  }

  var draftHabitTargetCountText: String {
    get { habitsStorage.draftHabitTargetCountText }
    set { habitsStorage.draftHabitTargetCountText = newValue }
  }

  /// Optional milestone-goal field text ("celebrate at N"); empty means no goal.
  var draftHabitMilestoneTargetText: String {
    get { habitsStorage.draftHabitMilestoneTargetText }
    set { habitsStorage.draftHabitMilestoneTargetText = newValue }
  }

  var draftHabitCadenceMode: HabitCadenceMode {
    get { habitsStorage.draftHabitCadenceMode }
    set { habitsStorage.draftHabitCadenceMode = newValue }
  }

  var draftHabitWeekdays: Set<Int> {
    get { habitsStorage.draftHabitWeekdays }
    set { habitsStorage.draftHabitWeekdays = newValue }
  }

  var draftHabitTimesPerWeek: Int {
    get { habitsStorage.draftHabitTimesPerWeek }
    set { habitsStorage.draftHabitTimesPerWeek = newValue }
  }

  var draftHabitDayOfMonth: Int {
    get { habitsStorage.draftHabitDayOfMonth }
    set { habitsStorage.draftHabitDayOfMonth = newValue }
  }

  var draftHabitIcon: String? {
    get { habitsStorage.draftHabitIcon }
    set { habitsStorage.draftHabitIcon = newValue }
  }

  var draftHabitColor: String? {
    get { habitsStorage.draftHabitColor }
    set { habitsStorage.draftHabitColor = newValue }
  }

  /// Reminder times ("HH:mm") to arm when the drafted habit is created.
  var draftHabitReminderTimes: [String] {
    get { habitsStorage.draftHabitReminderTimes }
    set { habitsStorage.draftHabitReminderTimes = newValue }
  }

  /// Cached completion history + stats for a single habit, used by the habit
  /// heatmap. Composed from the `getHabitCompletions` and `getHabitStats`
  /// servicing reads.
  struct HabitDetail: Equatable, Sendable {
    var completions: HabitCompletionsSnapshot
    var stats: HabitStats
    /// Reminder policies for the habit; drives the detail's reminder chips.
    var reminderPolicies: [HabitReminderPolicy] = []
  }

  /// Detail (completion history + stats) for `id`, or `nil` until loaded via
  /// `loadHabitDetail(id:)`.
  func habitDetail(for id: LorvexHabit.ID) -> HabitDetail? {
    habitsStorage.detailsByHabitID[id]
  }
}
