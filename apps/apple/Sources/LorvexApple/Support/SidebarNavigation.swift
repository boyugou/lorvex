import LorvexCore
import SwiftUI

extension SidebarSelection {
  /// The shared enum's English name ("Calendar", "Tasks", "Reviews"). The command
  /// palette matches it alongside ``macOSLocalizedTitle``, so a search for the
  /// data's plain name still finds the destination the sidebar calls Plan.
  var macOSDisplayTitle: String {
    title
  }

  var macOSLocalizedTitle: LocalizedStringResource {
    switch self {
    case .today: LocalizedStringResource("sidebar.item.today", defaultValue: "Today", table: "Localizable", bundle: LorvexL10n.bundle)
    case .tasks: LocalizedStringResource("sidebar.item.tasks", defaultValue: "All Tasks", table: "Localizable", bundle: LorvexL10n.bundle)
    case .lists: LocalizedStringResource("sidebar.item.lists", defaultValue: "Lists", table: "Localizable", bundle: LorvexL10n.bundle)
    case .calendar: LocalizedStringResource("sidebar.item.calendar", defaultValue: "Calendar", table: "Localizable", bundle: LorvexL10n.bundle)
    case .habits: LocalizedStringResource("sidebar.item.habits", defaultValue: "Habits", table: "Localizable", bundle: LorvexL10n.bundle)
    case .reviews: LocalizedStringResource("sidebar.item.reviews", defaultValue: "Review", table: "Localizable", bundle: LorvexL10n.bundle)
    case .memory: LocalizedStringResource("sidebar.item.memory", defaultValue: "Memory", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  /// Every fixed macOS destination, in flat command order. Drives the Navigate
  /// menu, command palette, keyboard accelerators, and launch-state validation.
  /// The sidebar renders a calmer subset plus dynamic task scopes: real user
  /// lists appear as sections that scope the Tasks surface rather than as more
  /// fixed abstract destinations.
  static let mainNavigationItems: [SidebarSelection] = [
    // The sidebar's destinations top to bottom, Memory from its pinned footer
    // included, so ⌘1–⌘6 walk them in order; then the Lists catalog, which has
    // no row of its own.
    .today, .calendar, .tasks, .reviews, .habits, .memory, .lists,
  ]

  /// The fixed sidebar destinations: the day, the week, every task, the review,
  /// and habits. Real lists follow them as sections rendered by `SidebarView`.
  /// Memory is the assistant's context rather than a place the user works, so it
  /// sits in the sidebar's pinned footer beside Settings instead of among them.
  static let sidebarGroups: [SidebarGroup] = [
    SidebarGroup(kind: .plan, items: [.today, .calendar, .tasks, .reviews, .habits])
  ]

  /// The `⌘`-modified accelerator for jumping to this destination from the
  /// Navigate menu, or `nil` for destinations with no assigned key. Uses digits
  /// for the first ten destinations and a mnemonic letter once the numeric row
  /// is exhausted.
  var navigationShortcut: KeyEquivalent? {
    switch self {
    case .today: "1"
    case .calendar: "2"
    case .tasks: "3"
    case .reviews: "4"
    case .habits: "5"
    case .memory: "6"
    // `.lists` has no sidebar row (lists are managed inline; the catalog is
    // reached via ⌘K), so it gets no numeric accelerator.
    case .lists: nil
    }
  }
}

/// A titled group of sidebar destinations. `kind` carries the localized section
/// header; `items` are the destinations shown under it.
struct SidebarGroup: Identifiable {
  let kind: SidebarGroupKind
  let items: [SidebarSelection]
  var id: SidebarGroupKind { kind }
}

enum SidebarGroupKind: Hashable {
  case plan
}
