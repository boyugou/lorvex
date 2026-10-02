import AppIntents

/// A task priority, offered in Shortcuts and Siri under the names the app
/// uses — High, Normal, Low — and passed to the runners as its level 1–3.
enum LorvexPriorityOption: String, AppEnum {
  case high
  case normal
  case low

  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.option.priority.type", defaultValue: "Priority", table: "Localizable", bundle: SystemL10n.bundle))
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .high: .init(title: LocalizedStringResource("system.option.priority.high", defaultValue: "High", table: "Localizable", bundle: SystemL10n.bundle)),
    .normal: .init(title: LocalizedStringResource("system.option.priority.normal", defaultValue: "Normal", table: "Localizable", bundle: SystemL10n.bundle)),
    .low: .init(title: LocalizedStringResource("system.option.priority.low", defaultValue: "Low", table: "Localizable", bundle: SystemL10n.bundle)),
  ]

  /// The stored priority level: 1 is high, 2 normal, 3 low.
  var level: Int {
    switch self {
    case .high: 1
    case .normal: 2
    case .low: 3
    }
  }
}
