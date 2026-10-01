import Foundation
import LorvexCore

/// Mobile's tab/task-only projection of a URL — the destination-to-tab mapping
/// this type owns has no equivalent in the shared route enum. Parsing always
/// delegates to ``LorvexDeepLinkRoute`` first (`init?(url:)`), so this can
/// never accept a host the shared resolver rejects, nor silently swallow one it
/// does not represent (`.list` / `.habit` / `.review` fall through to nil here
/// — a caller that needs to navigate to a specific list, habit, or review
/// entity routes the shared `LorvexDeepLinkRoute` through
/// `MobileStore.navigate(to:)` instead of through this narrower type).
public enum MobileDeepLinkRoute: Equatable, Sendable {
  public static let openHost = LorvexDeepLinkContract.openHost

  case tab(MobileTab)
  case task(LorvexTask.ID)

  public init?(url: URL) {
    guard let route = LorvexDeepLinkRoute(url: url) else { return nil }
    switch route {
    case .destination(let destination):
      guard let tab = Self.tabAndDestination(forDestination: destination.rawValue)
      else { return nil }
      self = .tab(tab)
    case .task(let id):
      self = .task(id)
    case .list, .habit, .review:
      return nil
    }
  }

  public var url: URL {
    switch self {
    case .tab(let tab):
      LorvexDeepLinkContract.destinationURL(Self.canonicalDestination(for: tab))
    case .task(let id):
      LorvexDeepLinkContract.taskURL(id)
    }
  }

  /// Produces the full navigation target for this route.
  public func navigationTarget(resolvedFrom url: URL? = nil) -> MobileNavigationTarget {
    switch self {
    case .tab(let tab):
      return MobileNavigationTarget(selectedTab: tab, route: nil)
    case .task(let id):
      return MobileNavigationTarget(selectedTab: .today, route: .task(id))
    }
  }

  /// Navigation target without URL context — identical to
  /// `navigationTarget(resolvedFrom:)`, since neither case reads `url`. Kept as
  /// a separate accessor for call sites that have no URL to hand.
  public var navigationTarget: MobileNavigationTarget {
    navigationTarget(resolvedFrom: nil)
  }

  /// Resolves a raw destination string (a `SidebarSelection` raw value, or the
  /// "review"/"reviews" alias) to the primary tab that now hosts it. Every
  /// domain workspace lives on a primary tab: Lists and Memory are reachable
  /// from the Tasks tab, Reviews from the Review tab.
  static func tabAndDestination(forDestination rawDestination: String) -> MobileTab? {
    if let sidebar = SidebarSelection.matching(rawDestination) {
      return tab(for: sidebar)
    }
    switch rawDestination.lowercased() {
    case "review", "reviews":
      return .review
    default:
      return nil
    }
  }

  private static func tab(for destination: SidebarSelection) -> MobileTab {
    switch destination {
    case .today: .today
    case .tasks: .tasks
    case .calendar: .calendar
    case .habits: .habits
    case .reviews: .review
    case .lists, .memory: .tasks
    }
  }

  private static func canonicalDestination(for tab: MobileTab) -> SidebarSelection {
    switch tab {
    case .today: .today
    case .tasks: .tasks
    case .calendar: .calendar
    case .habits: .habits
    case .review: .reviews
    }
  }
}

/// A fully-specified navigation destination within the mobile app.
///
/// `selectedTab` chooses the primary tab. `route` pushes a detail view within the today
/// tab's `NavigationStack`. `tasksRoute`, when set alongside `selectedTab == .tasks`,
/// pushes a route (e.g. a specific list) onto the Tasks tab's stack. `habitsRoute`, when
/// set alongside `selectedTab == .habits`, pushes a habit detail on the Habits tab's
/// stack, which `MobileStore.redirectHiddenHabitsTab` moves onto the Tasks stack
/// because the Habits tab is hidden from the bar.
public struct MobileNavigationTarget: Equatable, Sendable {
  public var selectedTab: MobileTab
  public var route: MobileRoute?
  /// Route to push on the Tasks tab's own stack. Ignored when `selectedTab != .tasks`.
  public var tasksRoute: MobileRoute?
  /// Route to push on the Habits tab's compact (iPhone) stack. Only meaningful when
  /// `selectedTab == .habits`.
  public var habitsRoute: MobileRoute?

  public init(
    selectedTab: MobileTab,
    route: MobileRoute?,
    tasksRoute: MobileRoute? = nil,
    habitsRoute: MobileRoute? = nil
  ) {
    self.selectedTab = selectedTab
    self.route = route
    self.tasksRoute = tasksRoute
    self.habitsRoute = habitsRoute
  }
}
