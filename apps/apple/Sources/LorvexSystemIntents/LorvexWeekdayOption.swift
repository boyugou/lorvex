import AppIntents

/// A day of the week, offered in Shortcuts and Siri as a localized weekday
/// name and written to a recurrence rule as its RRULE code.
enum LorvexWeekdayOption: String, AppEnum {
  case monday
  case tuesday
  case wednesday
  case thursday
  case friday
  case saturday
  case sunday

  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.option.weekday.type", defaultValue: "Weekday", table: "Localizable", bundle: SystemL10n.bundle))
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .monday: .init(title: LocalizedStringResource("system.option.weekday.monday", defaultValue: "Monday", table: "Localizable", bundle: SystemL10n.bundle)),
    .tuesday: .init(title: LocalizedStringResource("system.option.weekday.tuesday", defaultValue: "Tuesday", table: "Localizable", bundle: SystemL10n.bundle)),
    .wednesday: .init(title: LocalizedStringResource("system.option.weekday.wednesday", defaultValue: "Wednesday", table: "Localizable", bundle: SystemL10n.bundle)),
    .thursday: .init(title: LocalizedStringResource("system.option.weekday.thursday", defaultValue: "Thursday", table: "Localizable", bundle: SystemL10n.bundle)),
    .friday: .init(title: LocalizedStringResource("system.option.weekday.friday", defaultValue: "Friday", table: "Localizable", bundle: SystemL10n.bundle)),
    .saturday: .init(title: LocalizedStringResource("system.option.weekday.saturday", defaultValue: "Saturday", table: "Localizable", bundle: SystemL10n.bundle)),
    .sunday: .init(title: LocalizedStringResource("system.option.weekday.sunday", defaultValue: "Sunday", table: "Localizable", bundle: SystemL10n.bundle)),
  ]

  /// The two-letter RRULE `BYDAY` code for this day.
  var ruleCode: String {
    switch self {
    case .monday: "MO"
    case .tuesday: "TU"
    case .wednesday: "WE"
    case .thursday: "TH"
    case .friday: "FR"
    case .saturday: "SA"
    case .sunday: "SU"
    }
  }
}
