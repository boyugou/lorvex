import Foundation
import LorvexCore

/// Routes incoming NSUserActivity continuations from Handoff to MobileStore navigation state.
extension MobileStore {
  /// Applies the navigation state described by an `openTask` activity.
  public func continueOpenTaskActivity(_ activity: NSUserActivity) {
    guard let taskID = parseOpenTaskActivity(activity) else { return }
    openDeepLinkRoute(.task(taskID))
  }

  /// Applies the navigation state described by an `openDestination` activity.
  public func continueOpenDestinationActivity(_ activity: NSUserActivity) {
    guard let destination = parseOpenDestinationActivity(activity) else { return }
    navigate(to: .destination(destination))
  }

  /// Applies the navigation state described by an `openList` activity.
  /// Navigates to the Tasks tab and pushes the list's screen.
  public func continueOpenListActivity(_ activity: NSUserActivity) {
    guard let listID = parseOpenListActivity(activity) else { return }
    openNavigationTarget(
      MobileNavigationTarget(selectedTab: .tasks, route: nil, tasksRoute: .tasksScope(.list(listID)))
    )
  }

  /// Sets synchronous mobile navigation state for `route` and returns an async
  /// detail-load closure when the route needs one loaded (currently only a
  /// review-day switch, which awaits the daily-review read), or nil otherwise.
  /// The single mapping from the shared `LorvexDeepLinkRoute` to mobile
  /// navigation — used by ``navigate(to:)``, so URL (`openDeepLink`) and
  /// Handoff/Siri all land on the identical entity, not just its workspace:
  /// lists push the list's screen on the Tasks tab, habits select the
  /// habit and push its detail on the Habits tab, reviews select the Review tab
  /// and switch to the requested day, and tasks push the today-tab detail.
  /// Mirrors `AppStore.applyRouteNavigation` on macOS.
  @discardableResult
  func applyRouteNavigation(_ route: LorvexDeepLinkRoute) -> (() async -> Void)? {
    switch route {
    case .task(let id):
      openDeepLinkRoute(.task(id))
      return nil
    case .list(let id):
      openNavigationTarget(
        MobileNavigationTarget(selectedTab: .tasks, route: nil, tasksRoute: .tasksScope(.list(id)))
      )
      return nil
    case .habit(let id):
      openNavigationTarget(
        MobileNavigationTarget(selectedTab: .habits, route: nil, habitsRoute: .habit(id))
      )
      return nil
    case .review(let date):
      openNavigationTarget(MobileNavigationTarget(selectedTab: .review, route: nil))
      return { [weak self] in await self?.selectReviewDay(date) }
    case .destination(let destination):
      // Memory is a secondary workspace: open it the way the current layout
      // reaches it rather than landing on the Tasks home that hosts it.
      if destination == .memory {
        openWorkspaceDestination(.memory)
        return nil
      }
      guard let tab = MobileDeepLinkRoute.tabAndDestination(forDestination: destination.rawValue)
      else { return nil }
      openNavigationTarget(MobileNavigationTarget(selectedTab: tab, route: nil))
      return nil
    }
  }

  /// Routes any shared `LorvexDeepLinkRoute` — URL or Handoff/Siri — through
  /// mobile navigation, running the async load `applyRouteNavigation` returns
  /// (if any) after the synchronous state change so the surface lands instantly.
  func navigate(to route: LorvexDeepLinkRoute) {
    if let load = applyRouteNavigation(route) {
      Task { await load() }
    }
  }
}
