import AppIntents
import Foundation

struct ReadLorvexWeeklyReviewIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.review.weekly.read.title", defaultValue: "Read Lorvex Weekly Review", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.review.weekly.read.description", defaultValue: "Read the Lorvex weekly review snapshot.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.review.parameter.week_of", defaultValue: "Week Of", table: "Localizable", bundle: SystemL10n.bundle),
    kind: .date)
  var weekOf: Date?

  init() {}

  init(weekOf: Date? = nil) {
    self.weekOf = weekOf
  }

  /// Returns the week's five most recently completed tasks. Siri says how
  /// many tasks were completed this week, or in the week of the picked day.
  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexTaskEntity]> & ProvidesDialog {
    let review = try await LorvexTaskIntentRunner.readWeeklyReview(weekOf: weekOf.map(IntentDateText.day))
    let completed = review.topCompleted.map {
      LorvexTaskEntity(id: $0.id, title: $0.title, status: $0.status)
    }
    let count = review.completedThisWeek
    guard let weekOf else {
      return .result(
        value: completed,
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.review.weekly.read.dialog",
            defaultValue: "\(count) tasks completed this week.",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    let day = Self.weekDayLabel(weekOf)
    return .result(
      value: completed,
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.review.weekly.read.week_of_dialog",
          defaultValue: "\(count) tasks completed in the week of \(day).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }

  /// The picked day as the dialog names its week: month and day ("September
  /// 22"), with the year when it is not the current one.
  static func weekDayLabel(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
    var style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide).day()
    if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
      style = style.year()
    }
    return date.formatted(style)
  }
}
