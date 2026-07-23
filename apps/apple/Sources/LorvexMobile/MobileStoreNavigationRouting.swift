import Foundation
import LorvexCore

extension MobileStore {
  public func selectTask(_ id: LorvexTask.ID?) {
    selectedTaskID = id
  }

  public func selectList(_ id: LorvexList.ID?) {
    selectedListID = id
  }

  public func selectHabit(_ id: LorvexHabit.ID?) {
    selectedHabitID = id
  }

  public func selectMemoryEntry(_ id: MemoryEntry.ID?) {
    selectedMemoryKey = id
  }

  /// The `.onOpenURL` entry point for every external / system-delivered URL
  /// (custom-scheme links, widgets, notification taps that ask the system to
  /// open a URL). Parses through the shared `LorvexDeepLinkRoute` resolver —
  /// the same parser Handoff and Spotlight use — so a task/list/habit/review
  /// URL reaches ``navigate(to:)`` regardless of which surface delivered it,
  /// rather than through the narrower tab/task-only `MobileDeepLinkRoute`.
  public func openDeepLink(_ url: URL) {
    guard let route = LorvexDeepLinkRoute(url: url) else { return }
    navigate(to: route)
  }

  /// Applies a Home Screen / Dock quick action to the running mobile UI.
  ///
  /// `.quickCapture` presents the capture sheet immediately — matching the
  /// action's label and the macOS `focusQuickAdd` command — rather than merely
  /// navigating. Every other action routes through its deep link to the
  /// corresponding tab or destination.
  public func performQuickAction(_ action: LorvexQuickAction) {
    switch action {
    case .quickCapture:
      isPresentingCapture = true
    case .openToday:
      openDeepLink(action.deepLinkURL)
    }
  }

  public func openDeepLinkRoute(_ route: MobileDeepLinkRoute) {
    openNavigationTarget(route.navigationTarget)
  }

  public func openNavigationTarget(_ target: MobileNavigationTarget) {
    selectedTab = target.selectedTab
    routePath = target.route.map { [$0] } ?? []
    habitsRoutePath = target.habitsRoute.map { [$0] } ?? []
    if let route = target.route, case .task(let id) = route {
      selectedTaskID = id
    }
    if let habitsRoute = target.habitsRoute, case .habit(let id) = habitsRoute {
      selectedHabitID = id
    }
    if target.selectedTab != .more {
      moreNavigationPath = []
      iPadDestination = nil
      pendingListRoute = nil
    } else if let destination = target.moreDestination {
      moreNavigationPath = [destination]
      iPadDestination = destination
      pendingListRoute = target.moreListRoute
    }
  }

  public func openMoreDestination(_ destination: MobileDestination) {
    openNavigationTarget(MobileNavigationTarget(selectedTab: .more, route: nil, moreDestination: destination))
  }

  public func openTaskRouteOnCurrentStack(_ id: LorvexTask.ID) {
    selectedTaskID = id
    switch selectedTab {
    case .today:
      routePath.append(.task(id))
    case .tasks:
      tasksRoutePath.append(.task(id))
    case .more:
      pendingListRoute = .task(id)
    case .calendar, .habits:
      // No programmatic-open caller on these tabs; selection above is enough.
      break
    }
  }

  public func applyPendingIntentHandoff() {
    guard let target = MobileIntentHandoff.consumeNavigationTarget() else { return }
    openNavigationTarget(target)
  }
}
