import LorvexCore
import SwiftUI

extension SidebarSelection {
  /// Product-facing title for macOS navigation. The shared enum case remains
  /// `.calendar` because the backing data is a calendar timeline, and the Mac
  /// surface should describe that durable mental model directly.
  var macOSDisplayTitle: String {
    title
  }

  var macOSLocalizedTitle: LocalizedStringResource {
    switch self {
    case .today: LocalizedStringResource("sidebar.item.today", defaultValue: "Today", table: "Localizable", bundle: LorvexL10n.bundle)
    case .tasks: LocalizedStringResource("sidebar.item.tasks", defaultValue: "Tasks", table: "Localizable", bundle: LorvexL10n.bundle)
    case .lists: LocalizedStringResource("sidebar.item.lists", defaultValue: "Lists", table: "Localizable", bundle: LorvexL10n.bundle)
    case .calendar: LocalizedStringResource("sidebar.item.calendar", defaultValue: "Calendar", table: "Localizable", bundle: LorvexL10n.bundle)
    case .habits: LocalizedStringResource("sidebar.item.habits", defaultValue: "Habits", table: "Localizable", bundle: LorvexL10n.bundle)
    case .reviews: LocalizedStringResource("sidebar.item.reviews", defaultValue: "Reviews", table: "Localizable", bundle: LorvexL10n.bundle)
    case .memory: LocalizedStringResource("sidebar.item.memory", defaultValue: "Memory", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  /// Every fixed macOS destination, in flat command order. Drives the Navigate
  /// menu, command palette, keyboard accelerators, and launch-state validation.
  /// The sidebar renders a calmer subset plus dynamic task scopes: real user
  /// lists appear as sections that scope the Tasks surface rather than as more
  /// fixed abstract destinations.
  static let mainNavigationItems: [SidebarSelection] = [
    // The macOS app's human surfaces, in sidebar order.
    .today, .calendar, .tasks, .lists, .habits, .reviews, .memory,
  ]

  /// The fixed sidebar destinations: only the durable Plan and Reflect surfaces.
  /// Real Lists are rendered by `SidebarView` from user data
  /// between Plan and Reflect; AI-owned analytical/transparency surfaces stay in
  /// the Navigate menu, command palette, or MCP layer.
  static let sidebarGroups: [SidebarGroup] = [
    SidebarGroup(kind: .plan, items: [.today, .calendar, .tasks]),
    SidebarGroup(kind: .reflect, items: [.habits, .reviews, .memory]),
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
    case .habits: "4"
    case .reviews: "5"
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
  case reflect

  var localizedTitle: LocalizedStringResource {
    switch self {
    case .plan: LocalizedStringResource("sidebar.section.plan", defaultValue: "Plan", table: "Localizable", bundle: LorvexL10n.bundle)
    case .reflect: LocalizedStringResource("sidebar.section.reflect", defaultValue: "Reflect", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}
