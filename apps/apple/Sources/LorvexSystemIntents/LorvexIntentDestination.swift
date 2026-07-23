import AppIntents
import LorvexCore

enum LorvexIntentDestination: String, AppEnum {
  case today
  case tasks
  case lists
  case calendar
  case habits
  case reviews
  case memory

  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.destination.type", defaultValue: "Lorvex Destination", table: "Localizable", bundle: SystemL10n.bundle))

  static let caseDisplayRepresentations: [LorvexIntentDestination: DisplayRepresentation] = [
    .today: DisplayRepresentation(
      title: LocalizedStringResource("system.destination.today", defaultValue: "Today", table: "Localizable", bundle: SystemL10n.bundle),
      image: .init(systemName: "sun.max")),
    .tasks: DisplayRepresentation(
      title: LocalizedStringResource("system.destination.tasks", defaultValue: "Tasks", table: "Localizable", bundle: SystemL10n.bundle),
      image: .init(systemName: "checklist")),
    .lists: DisplayRepresentation(
      title: LocalizedStringResource("system.destination.lists", defaultValue: "Lists", table: "Localizable", bundle: SystemL10n.bundle),
      image: .init(systemName: "tray.full")),
    .calendar: DisplayRepresentation(
      title: LocalizedStringResource("system.destination.calendar", defaultValue: "Calendar", table: "Localizable", bundle: SystemL10n.bundle),
      image: .init(systemName: "calendar")),
    .habits: DisplayRepresentation(
      title: LocalizedStringResource("system.destination.habits", defaultValue: "Habits", table: "Localizable", bundle: SystemL10n.bundle),
      image: .init(systemName: "repeat.circle")),
    .reviews: DisplayRepresentation(
      title: LocalizedStringResource("system.destination.reviews", defaultValue: "Reviews", table: "Localizable", bundle: SystemL10n.bundle),
      image: .init(systemName: "text.badge.checkmark")),
    .memory: DisplayRepresentation(
      title: LocalizedStringResource("system.destination.memory", defaultValue: "Memory", table: "Localizable", bundle: SystemL10n.bundle),
      image: .init(systemName: "brain")),
  ]

  var openDialog: LocalizedStringResource {
    switch self {
    case .today:
      LocalizedStringResource(
        "system.open.dialog.today",
        defaultValue: "Opening Today in Lorvex.",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    case .tasks:
      LocalizedStringResource(
        "system.open.dialog.tasks",
        defaultValue: "Opening Tasks in Lorvex.",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    case .lists:
      LocalizedStringResource(
        "system.open.dialog.lists",
        defaultValue: "Opening Lists in Lorvex.",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    case .calendar:
      LocalizedStringResource(
        "system.open.dialog.calendar",
        defaultValue: "Opening Calendar in Lorvex.",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    case .habits:
      LocalizedStringResource(
        "system.open.dialog.habits",
        defaultValue: "Opening Habits in Lorvex.",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    case .reviews:
      LocalizedStringResource(
        "system.open.dialog.reviews",
        defaultValue: "Opening Reviews in Lorvex.",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    case .memory:
      LocalizedStringResource(
        "system.open.dialog.memory",
        defaultValue: "Opening Memory in Lorvex.",
        table: "Localizable",
        bundle: SystemL10n.bundle)
    }
  }

  var sidebarSelection: SidebarSelection {
    switch self {
    case .today: .today
    case .tasks: .tasks
    case .lists: .lists
    case .calendar: .calendar
    case .habits: .habits
    case .reviews: .reviews
    case .memory: .memory
    }
  }
}
