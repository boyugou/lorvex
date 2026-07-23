import LorvexCore

extension MobileStore {
  public struct HabitDetail: Equatable, Sendable {
    public var completions: HabitCompletionsSnapshot
    public var stats: HabitStats
    public var reminderPolicies: [HabitReminderPolicy]

    public init(
      completions: HabitCompletionsSnapshot,
      stats: HabitStats,
      reminderPolicies: [HabitReminderPolicy]
    ) {
      self.completions = completions
      self.stats = stats
      self.reminderPolicies = reminderPolicies
    }
  }

  public func habitDetail(for id: LorvexHabit.ID) -> HabitDetail? {
    habitDetailsByID[id]
  }
}
