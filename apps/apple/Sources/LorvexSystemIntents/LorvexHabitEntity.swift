import AppIntents
import LorvexCore

struct LorvexHabitEntity: AppEntity, Identifiable {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.entity.habit.type", defaultValue: "Lorvex Habit", table: "Localizable", bundle: SystemL10n.bundle))
  static let defaultQuery = LorvexHabitEntityQuery()

  var id: LorvexHabit.ID
  var name: String
  var completionsToday: Int
  var targetCount: Int
  /// The habit's cadence (`daily`, `weekly`, `times_per_week`, `monthly`,
  /// `custom`), which names the unit its streak counts in.
  var frequencyType: String
  /// Today was set aside for the habit, which the subtitle says in place of
  /// its count.
  var isSkipped: Bool

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(name)",
      subtitle: isSkipped
        ? LocalizedStringResource(
          "system.entity.habit.skipped.today",
          defaultValue: "Skipped today",
          table: "Localizable",
          bundle: SystemL10n.bundle)
        : LocalizedStringResource(
          "system.entity.habit.progress.today",
          defaultValue: "\(completionsToday)/\(targetCount) today",
          table: "Localizable",
          bundle: SystemL10n.bundle),
      image: .init(systemName: "repeat.circle")
    )
  }

  init(
    id: LorvexHabit.ID, name: String, completionsToday: Int, targetCount: Int,
    frequencyType: String = "daily", isSkipped: Bool = false
  ) {
    self.id = id
    self.name = name
    self.completionsToday = completionsToday
    self.targetCount = targetCount
    self.frequencyType = frequencyType
    self.isSkipped = isSkipped
  }

  init(habit: LorvexHabit) {
    self.init(
      id: habit.id,
      name: habit.name,
      completionsToday: habit.completionsToday,
      targetCount: habit.targetCount,
      frequencyType: habit.frequencyType,
      isSkipped: habit.isSkipped
    )
  }
}
