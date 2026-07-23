import AppIntents

struct SetLorvexTaskRecurrenceIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.recurrence.set.title", defaultValue: "Set Lorvex Task Recurrence", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.recurrence.set.description", defaultValue: "Set a Lorvex task recurrence rule.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.frequency", defaultValue: "Frequency", table: "Localizable", bundle: SystemL10n.bundle))
  var frequency: LorvexRecurrenceFrequencyOption

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.interval", defaultValue: "Interval", table: "Localizable", bundle: SystemL10n.bundle))
  var interval: Int?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.weekdays", defaultValue: "Weekdays", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.task.parameter.weekdays.optional_codes.description", defaultValue: "Optional weekday codes such as MO, WE, FR.", table: "Localizable", bundle: SystemL10n.bundle))
  var weekdays: String?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.until", defaultValue: "Until", table: "Localizable", bundle: SystemL10n.bundle))
  var until: String?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.count", defaultValue: "Count", table: "Localizable", bundle: SystemL10n.bundle))
  var count: Int?

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
    frequency = .weekly
  }

  init(
    task: LorvexTaskEntity,
    frequency: LorvexRecurrenceFrequencyOption,
    interval: Int? = nil,
    weekdays: String? = nil,
    until: String? = nil,
    count: Int? = nil
  ) {
    self.task = task
    self.frequency = frequency
    self.interval = interval
    self.weekdays = weekdays
    self.until = until
    self.count = count
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let updated = try await LorvexTaskIntentRunner.setTaskRecurrence(
      taskID: task.id,
      frequency: frequency.ruleFrequency,
      interval: interval,
      weekdaysText: weekdays,
      until: until,
      count: count
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.recurrence.set.dialog", defaultValue: "Set recurrence for \(updated.title).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
