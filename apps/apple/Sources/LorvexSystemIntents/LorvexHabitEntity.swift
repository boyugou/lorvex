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

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(name)",
      subtitle: LocalizedStringResource(
        "system.entity.habit.progress.today",
        defaultValue: "\(completionsToday)/\(targetCount) today",
        table: "Localizable",
        bundle: SystemL10n.bundle),
      image: .init(systemName: "repeat.circle")
    )
  }

  init(
    id: LorvexHabit.ID, name: String, completionsToday: Int, targetCount: Int,
    frequencyType: String = "daily"
  ) {
    self.id = id
    self.name = name
    self.completionsToday = completionsToday
    self.targetCount = targetCount
    self.frequencyType = frequencyType
  }

  init(habit: LorvexHabit) {
    self.init(
      id: habit.id,
      name: habit.name,
      completionsToday: habit.completionsToday,
      targetCount: habit.targetCount,
      frequencyType: habit.frequencyType
    )
  }
}
