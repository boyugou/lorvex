import AppIntents
import Foundation

struct ReadLorvexHabitCompletionsIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.habit.completions.read.title", defaultValue: "Read Lorvex Habit Completions", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.habit.completions.read.description", defaultValue: "Read Lorvex habit completion history.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.habit.parameter.habit", defaultValue: "Habit", table: "Localizable", bundle: SystemL10n.bundle))
  var habit: LorvexHabitEntity

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.from", defaultValue: "From", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var from: Date?

  @Parameter(
    title: LocalizedStringResource("system.calendar.parameter.to", defaultValue: "To", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var to: Date?

  init() {
    habit = LorvexHabitEntity(id: "", name: "", completionsToday: 0, targetCount: 0)
    from = nil
    to = nil
  }

  init(habit: LorvexHabitEntity, from: Date? = nil, to: Date? = nil) {
    self.habit = habit
    self.from = from
    self.to = to
  }

  /// Returns the days the habit was done, each as the start of that day on
  /// the device's calendar.
  func perform() async throws -> some IntentResult & ReturnsValue<[Date]> & ProvidesDialog {
    let range = IntentDateText.dayRange(from: from, to: to)
    let snapshot = try await LorvexTaskIntentRunner.readHabitCompletions(
      id: habit.id,
      from: range.from,
      to: range.to
    )
    let count = snapshot.completions.count
    return .result(
      value: Self.days(snapshot.completions.map(\.completedDate)),
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.habit.completions.read.dialog_count",
          defaultValue: "\(habit.name) has \(count) completions.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }

  /// Each `yyyy-MM-dd` day key as midnight of that day in `calendar`, so
  /// Shortcuts shows the same day the habit was done; keys that do not parse
  /// are left out.
  static func days(_ dayKeys: [String], calendar: Calendar = .current) -> [Date] {
    dayKeys.compactMap { key in
      let parts = key.split(separator: "-").compactMap { Int($0) }
      guard parts.count == 3 else { return nil }
      return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
  }
}
