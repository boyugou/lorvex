import AppIntents
import LorvexCore

struct ReadLorvexDayTimesIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.day_times.read.title", defaultValue: "Read Lorvex Schedule", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.day_times.read.description", defaultValue: "Read the Lorvex tasks with a time today or on a specific date.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.date", defaultValue: "Date", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.parameter.date.today_when_blank.description", defaultValue: "Leave blank for today.", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var date: Date?

  init() {
    date = nil
  }

  init(date: Date?) {
    self.date = date
  }

  /// Returns the day's timed tasks in time order.
  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexTaskEntity]> & ProvidesDialog {
    let day = try await LorvexTaskIntentRunner.readDayTimes(date: date.map(IntentDateText.day))
    let tasks = day.tasks.map(LorvexTaskEntity.init(task:))
    guard let first = day.tasks.first, let time = first.plannedTime else {
      return .result(
        value: tasks,
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.day_times.read.none_dialog", defaultValue: "No tasks have a time on \(lorvexDayLine(logicalDay: day.date)).",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    let count = day.tasks.count
    let start = lorvexClockTimeLabel(minutes: time.lowerBound)
    return .result(
      value: tasks,
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.day_times.read.dialog",
          defaultValue: "\(count) tasks have a time on \(lorvexDayLine(logicalDay: day.date)), starting with \(first.title) at \(start).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
