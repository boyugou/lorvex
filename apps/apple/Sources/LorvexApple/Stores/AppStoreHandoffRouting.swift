@preconcurrency import CoreSpotlight
import Foundation
import LorvexCore

/// Routes incoming NSUserActivity continuations (Handoff, Siri, Spotlight) to
/// AppStore navigation state through the single `LorvexDeepLinkRoute` resolver.
extension AppStore {
  /// Resolves any continuation `NSUserActivity` — Handoff/Siri (typed) or a
  /// Spotlight result tap (`CSSearchableItemActionType`, carrying the item's
  /// `uniqueIdentifier`) — to a `LorvexDeepLinkRoute` and routes it through the
  /// shared navigation path.
  func continueActivity(_ activity: NSUserActivity) {
    guard let route = resolveRoute(from: activity) else { return }
    // Set navigation state synchronously so the surface lands immediately;
    // any detail load runs after.
    if let load = applyRouteNavigation(route) {
      Task { await load() }
    }
  }

  private func resolveRoute(from activity: NSUserActivity) -> LorvexDeepLinkRoute? {
    if let route = LorvexDeepLinkRoute(activity: activity) {
      return route
    }
    if activity.activityType == CSSearchableItemActionType,
      let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
    {
      return LorvexDeepLinkRoute(spotlightIdentifier: identifier)
    }
    return nil
  }
}
