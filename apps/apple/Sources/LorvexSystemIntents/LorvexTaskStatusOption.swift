import AppIntents

/// Selectable task status filter for list/search queries. Case rawValues are
/// the wire-format strings accepted by the core's task status filters
/// (`open`, `in_progress`, `someday`, `completed`, `cancelled`), plus the `all`
/// sentinel that removes the status filter entirely — already a first-class
/// value accepted by `listTasks`/`searchTasks`, not just an omission of the
/// parameter. `inProgress` is the started marker; it is actionable and surfaces
/// wherever `open` does.
enum LorvexTaskStatusOption: String, AppEnum {
  case all
  case open
  case inProgress = "in_progress"
  case someday
  case completed
  case cancelled

  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.option.task_status.type", defaultValue: "Task Status", table: "Localizable", bundle: SystemL10n.bundle))
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .all: .init(title: LocalizedStringResource("system.option.task_status.all", defaultValue: "All", table: "Localizable", bundle: SystemL10n.bundle)),
    .open: .init(title: LocalizedStringResource("system.option.task_status.open", defaultValue: "Open", table: "Localizable", bundle: SystemL10n.bundle)),
    .inProgress: .init(title: LocalizedStringResource("system.option.task_status.in_progress", defaultValue: "In Progress", table: "Localizable", bundle: SystemL10n.bundle)),
    .someday: .init(title: LocalizedStringResource("system.option.task_status.someday", defaultValue: "Someday", table: "Localizable", bundle: SystemL10n.bundle)),
    .completed: .init(title: LocalizedStringResource("system.option.task_status.completed", defaultValue: "Completed", table: "Localizable", bundle: SystemL10n.bundle)),
    .cancelled: .init(title: LocalizedStringResource("system.option.task_status.cancelled", defaultValue: "Cancelled", table: "Localizable", bundle: SystemL10n.bundle)),
  ]

  /// The localized display title for a raw task-status wire string
  /// (`open` / `in_progress` / `someday` / `completed` / `cancelled`), so an
  /// entity picker subtitle shows "Open" instead of the raw wire enum. Reuses
  /// ``caseDisplayRepresentations`` so the label lives in one place; falls back
  /// to the raw value for an unrecognized status.
  static func localizedLabel(forRawStatus raw: String) -> LocalizedStringResource {
    guard let option = LorvexTaskStatusOption(rawValue: raw),
      let title = caseDisplayRepresentations[option]?.title
    else { return LocalizedStringResource(stringLiteral: raw) }
    return title
  }
}
