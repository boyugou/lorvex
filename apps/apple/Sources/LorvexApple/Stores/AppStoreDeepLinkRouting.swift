import Foundation
import LorvexCore
import LorvexSystemIntents

extension AppStore {
  func applyPendingIntentHandoff() {
    if let taskID = LorvexIntentHandoff.consumeTaskID() {
      selectedTaskID = taskID
      selection = .tasks
      syncSelectedTaskDraft()
      return
    }
    guard let destination = LorvexIntentHandoff.consumeDestination() else { return }
    selection = destination
  }

  func openDeepLink(_ url: URL) async {
    guard let route = LorvexDeepLinkRoute(url: url) else { return }
    await openDeepLinkRoute(route)
  }

  func openDeepLinkRoute(_ route: LorvexDeepLinkRoute) async {
    if let load = applyRouteNavigation(route) {
      await load()
    }
  }

  /// Sets the synchronous navigation state for `route` (so continuation surfaces
  /// navigate instantly) and returns an async detail-load closure when the route
  /// needs one loaded (an off-screen task, a list detail, or a review-day
  /// switch), or nil otherwise. The single entry point shared by deep links,
  /// Handoff/Siri, and Spotlight.
  @discardableResult
  func applyRouteNavigation(_ route: LorvexDeepLinkRoute) -> (() async -> Void)? {
    switch route {
    case .destination(let destination):
      selection = destination
      return nil
    case .task(let id):
      selectedTaskID = id
      selection = .tasks
      if taskForFocusSurface(id: id) != nil {
        syncSelectedTaskDraft()
        return nil
      }
      return { [weak self] in await self?.loadSelectedTaskDetail() }
    case .list(let id):
      selectedListID = id
      selection = .lists
      return { [weak self] in await self?.loadSelectedListDetailForUI() }
    case .habit(let id):
      selectedHabitID = id
      selection = .habits
      return nil
    case .review(let date):
      selection = .reviews
      return { [weak self] in await self?.selectReviewDay(date) }
    }
  }
}
