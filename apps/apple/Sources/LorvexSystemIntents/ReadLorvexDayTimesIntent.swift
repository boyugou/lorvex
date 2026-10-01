import AppIntents
import LorvexCore

struct ReadLorvexDayTimesIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.day_times.read.title", defaultValue: "Read Lorvex Schedule", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.day_times.read.description", defaultValue: "Read the Lorvex tasks with a time today or on a specific date.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.date", defaultValue: "Date", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.task.parameter.date.optional_today.description", defaultValue: "Optional date in YYYY-MM-DD format. Leave blank for today.", table: "Localizable", bundle: SystemL10n.bundle))
  var date: String?

  init() {
    date = nil
  }

  init(date: String?) {
    self.date = date
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let day = try await LorvexTaskIntentRunner.readDayTimes(date: date)
    guard let first = day.tasks.first, let time = first.plannedTime else {
      return .result(
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.day_times.read.none_dialog", defaultValue: "No tasks have a time on \(day.date).",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    let count = day.tasks.count
    let start = lorvexClockTimeLabel(minutes: time.lowerBound)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.day_times.read.dialog",
          defaultValue: "\(count) tasks have a time on \(day.date), starting with \(first.title) at \(start).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
