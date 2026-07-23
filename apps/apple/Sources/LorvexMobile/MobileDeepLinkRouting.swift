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
      guard let (tab, _) = Self.tabAndDestination(forDestination: destination.rawValue)
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

  /// Produces the full navigation target, including a `moreDestination` when
  /// this route targets a domain workspace within the More tab.
  public func navigationTarget(resolvedFrom url: URL? = nil) -> MobileNavigationTarget {
    switch self {
    case .tab(let tab):
      let moreDestination: MobileDestination?
      if tab == .more, let url {
        moreDestination = Self.moreDestination(from: url)
      } else {
        moreDestination = nil
      }
      return MobileNavigationTarget(selectedTab: tab, route: nil, moreDestination: moreDestination)
    case .task(let id):
      return MobileNavigationTarget(selectedTab: .today, route: .task(id), moreDestination: nil)
    }
  }

  /// Navigation target without URL context, so `moreDestination` is always `nil`.
  public var navigationTarget: MobileNavigationTarget {
    navigationTarget(resolvedFrom: nil)
  }

  private static func moreDestination(from url: URL) -> MobileDestination? {
    let host = url.host()?.lowercased() ?? ""
    let pathComponents = url.pathComponents.filter { $0 != "/" }
    let rawDestination: String
    if host == Self.openHost, let first = pathComponents.first {
      rawDestination = first
    } else {
      rawDestination = host
    }
    return tabAndDestination(forDestination: rawDestination)?.1
  }

  static func tabAndDestination(forDestination rawDestination: String)
    -> (MobileTab, MobileDestination?)?
  {
    if let sidebar = SidebarSelection.matching(rawDestination) {
      let tab = tab(for: sidebar)
      let dest: MobileDestination? = tab == .more ? mobileDestination(for: sidebar) : nil
      return (tab, dest)
    }
    switch rawDestination.lowercased() {
    case "review", "reviews":
      return (.more, .review)
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
    case .lists, .memory, .reviews:
      .more
    }
  }

  private static func mobileDestination(for sidebar: SidebarSelection) -> MobileDestination? {
    switch sidebar {
    case .lists: .lists
    case .memory: .memory
    case .reviews: .review
    default: nil
    }
  }

  private static func canonicalDestination(for tab: MobileTab) -> SidebarSelection {
    switch tab {
    case .today: .today
    case .tasks: .tasks
    case .calendar: .calendar
    case .habits: .habits
    case .more: .tasks
    }
  }
}

/// A fully-specified navigation destination within the mobile app.
///
/// `selectedTab` chooses the primary tab. `route` pushes a detail view within the today
/// tab's `NavigationStack`. `moreDestination`, when set alongside `selectedTab == .more`,
/// pushes a domain workspace in the More tab's navigation stack. `moreListRoute`, when set
/// alongside `moreDestination == .lists`, pushes a list detail on top of the workspace.
/// `habitsRoute`, when set alongside `selectedTab == .habits`, pushes a habit detail on the
/// Habits tab's `NavigationStack` (the iPad/visionOS regular layout shows habit detail via
/// selection instead, so this is a no-op there — see `MobileStore.habitsRoutePath`).
public struct MobileNavigationTarget: Equatable, Sendable {
  public var selectedTab: MobileTab
  public var route: MobileRoute?
  /// Workspace destination to push inside the More tab's navigation stack.
  /// Ignored when `selectedTab != .more`.
  public var moreDestination: MobileDestination?
  /// List route to push on top of the Lists workspace inside the More tab.
  /// Only meaningful when `moreDestination == .lists`.
  public var moreListRoute: MobileRoute?
  /// Habit route to push on top of the Habits tab's compact (iPhone) stack.
  /// Only meaningful when `selectedTab == .habits`.
  public var habitsRoute: MobileRoute?

  public init(
    selectedTab: MobileTab,
    route: MobileRoute?,
    moreDestination: MobileDestination? = nil,
    moreListRoute: MobileRoute? = nil,
    habitsRoute: MobileRoute? = nil
  ) {
    self.selectedTab = selectedTab
    self.route = route
    self.moreDestination = moreDestination
    self.moreListRoute = moreListRoute
    self.habitsRoute = habitsRoute
  }
}
