import Foundation
import LorvexCore

/// Routes incoming NSUserActivity continuations from Handoff to MobileStore navigation state.
extension MobileStore {
  /// Applies the navigation state described by an `openTask` activity.
  public func continueOpenTaskActivity(_ activity: NSUserActivity) {
    guard let taskID = parseOpenTaskActivity(activity) else { return }
    navigate(to: .task(taskID))
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
    navigate(to: .list(listID))
  }

  /// Sets the synchronous navigation state for `route` and returns the async
  /// load the route still needs, or nil. Only a review day needs one: Review is
  /// selected at once, and switching to the requested day awaits the
  /// daily-review read. Where each route lands is
  /// `MobileNavigationTarget.init(route:)`, so a URL (`openDeepLink`),
  /// Handoff, and Siri all open the identical entity, not just its workspace.
  /// Mirrors `AppStore.applyRouteNavigation` on macOS.
  @discardableResult
  func applyRouteNavigation(_ route: LorvexDeepLinkRoute) -> (() async -> Void)? {
    openNavigationTarget(MobileNavigationTarget(route: route))
    guard case .review(let date) = route else { return nil }
    return { [weak self] in await self?.selectReviewDay(date) }
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
