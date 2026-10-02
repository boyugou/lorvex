import Foundation
import LorvexCore

/// A place in the iPhone and iPad app: the tab to select and the screens to
/// stack on that tab, root first. Every external entry point (a `lorvex://`
/// URL, Handoff, Siri, Spotlight, a notification, a Shortcuts handoff) lands
/// through one of these, so a link opens the same screen however it arrived.
public struct MobileNavigationTarget: Equatable, Sendable {
  public var selectedTab: MobileTab
  /// The screens pushed on `selectedTab`'s stack, root first. Empty shows the
  /// tab's root.
  public var path: [MobileRoute]

  public init(selectedTab: MobileTab, path: [MobileRoute] = []) {
    self.selectedTab = selectedTab
    self.path = path
  }

  /// Where a shared deep-link route lands. A task opens its detail over Today.
  /// A list opens its screen on the Tasks tab. A habit opens its detail above
  /// the Habits workspace on the Tasks tab, the same stack the Tasks home's
  /// Habits row builds. A review day selects the Review tab; switching to the
  /// day itself awaits a read, which the store runs after landing.
  public init(route: LorvexDeepLinkRoute) {
    switch route {
    case .task(let id):
      self.init(selectedTab: .today, path: [.task(id)])
    case .list(let id):
      self.init(selectedTab: .tasks, path: [.tasksScope(.list(id))])
    case .habit(let id):
      self.init(selectedTab: .tasks, path: [.workspace(.habits), .habit(id)])
    case .review:
      self.init(selectedTab: .review)
    case .destination(let destination):
      self.init(destination: destination)
    }
  }

  /// Where a shared workspace destination lands. Today, Calendar, Tasks, and
  /// Reviews open their tab at its root, and Lists opens the Tasks home, where
  /// lists live. Habits and Memory are workspaces rather than tabs, pushed onto
  /// the Tasks tab the way the Tasks home's rows push them.
  public init(destination: SidebarSelection) {
    switch destination {
    case .today: self.init(selectedTab: .today)
    case .calendar: self.init(selectedTab: .calendar)
    case .tasks, .lists: self.init(selectedTab: .tasks)
    case .reviews: self.init(selectedTab: .review)
    case .habits: self.init(selectedTab: .tasks, path: [.workspace(.habits)])
    case .memory: self.init(selectedTab: .tasks, path: [.workspace(.memory)])
    }
  }
}
