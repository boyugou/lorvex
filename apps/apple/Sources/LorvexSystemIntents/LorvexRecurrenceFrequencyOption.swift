import AppIntents
import LorvexCore

enum LorvexRecurrenceFrequencyOption: String, AppEnum {
  case daily
  case weekly
  case monthly
  case yearly

  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.option.recurrence_frequency.type", defaultValue: "Recurrence Frequency", table: "Localizable", bundle: SystemL10n.bundle))
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .daily: .init(title: LocalizedStringResource("system.option.recurrence_frequency.daily", defaultValue: "Daily", table: "Localizable", bundle: SystemL10n.bundle)),
    .weekly: .init(title: LocalizedStringResource("system.option.recurrence_frequency.weekly", defaultValue: "Weekly", table: "Localizable", bundle: SystemL10n.bundle)),
    .monthly: .init(title: LocalizedStringResource("system.option.recurrence_frequency.monthly", defaultValue: "Monthly", table: "Localizable", bundle: SystemL10n.bundle)),
    .yearly: .init(title: LocalizedStringResource("system.option.recurrence_frequency.yearly", defaultValue: "Yearly", table: "Localizable", bundle: SystemL10n.bundle)),
  ]

  var ruleFrequency: TaskRecurrenceRule.Frequency {
    switch self {
    case .daily: .daily
    case .weekly: .weekly
    case .monthly: .monthly
    case .yearly: .yearly
    }
  }
}
