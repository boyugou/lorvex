import AppIntents

/// Selectable calendar provider source for task-to-event provider links. Only
/// `eventkit` ships a writer/refresh path, so it is the sole option (mirroring
/// the core's reduced `ProviderKind` allowlist); ``wireValue`` carries the
/// snake_case wire string. Additional providers are added here deliberately when
/// their real ingestion adapter lands.
enum LorvexProviderSourceOption: String, AppEnum {
  case eventkit

  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.option.provider_source.type", defaultValue: "Provider Source", table: "Localizable", bundle: SystemL10n.bundle))
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .eventkit: .init(title: LocalizedStringResource("system.option.provider_source.eventkit", defaultValue: "EventKit", table: "Localizable", bundle: SystemL10n.bundle)),
  ]

  /// Wire-format string sent to `linkTaskToProviderEvent`, matching the core's
  /// `ProviderKind` allowlist.
  var wireValue: String {
    switch self {
    case .eventkit: "eventkit"
    }
  }
}
