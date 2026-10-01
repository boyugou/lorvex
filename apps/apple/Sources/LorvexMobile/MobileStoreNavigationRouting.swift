import Foundation
import LorvexCore

extension MobileStore {
  public func selectTask(_ id: LorvexTask.ID?) {
    selectedTaskID = id
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
    tasksRoutePath = target.tasksRoute.map { [$0] } ?? []
    habitsRoutePath = target.habitsRoute.map { [$0] } ?? []
    // Calendar carries no target-route field. Every jump through this entry
    // point (deep link / Handoff / intent) clears it so it lands on a clean
    // root rather than a stale pushed detail.
    calendarRoutePath = []
    if let route = target.route, case .task(let id) = route {
      selectedTaskID = id
    }
    if let habitsRoute = target.habitsRoute, case .habit(let id) = habitsRoute {
      selectedHabitID = id
    }
  }

  /// Opens a destination. Primary-tab destinations select their tab (Lists is
  /// the Tasks home itself). Memory and Settings are secondary workspaces
  /// pushed onto their hosting tab's stack (Memory on Tasks, Settings on Today).
  public func openWorkspaceDestination(_ destination: MobileDestination) {
    switch destination {
    case .tasks, .lists:
      openPrimaryShortcutTab(.tasks)
    case .calendar:
      openPrimaryShortcutTab(.calendar)
    case .habits:
      openPrimaryShortcutTab(.habits)
    case .review:
      openPrimaryShortcutTab(.review)
    case .memory:
      openSecondaryWorkspace(destination, hostTab: .tasks)
    case .settings:
      openSecondaryWorkspace(destination, hostTab: .today)
    }
  }

  private func openSecondaryWorkspace(_ destination: MobileDestination, hostTab: MobileTab) {
    openPrimaryShortcutTab(hostTab)
    let route = MobileRoute.workspace(destination)
    switch hostTab {
    case .today: routePath = [route]
    case .tasks: tasksRoutePath = [route]
    case .calendar: calendarRoutePath = [route]
    case .habits: habitsRoutePath = [route]
    case .review: reviewRoutePath = [route]
    }
  }

  public func openTaskRouteOnCurrentStack(_ id: LorvexTask.ID) {
    selectedTaskID = id
    switch selectedTab {
    case .today:
      routePath.append(.task(id))
    case .tasks:
      tasksRoutePath.append(.task(id))
    case .calendar:
      calendarRoutePath.append(.task(id))
    case .habits:
      // No programmatic task-open caller on Habits; selection above is enough.
      break
    case .review:
      reviewRoutePath.append(.task(id))
    }
  }

  /// Push a list's screen onto the active tab's stack rather than switching
  /// tabs. Only the Tasks and Today stacks show lists; on the other tabs the
  /// push is skipped.
  public func openListRouteOnCurrentStack(_ id: LorvexList.ID) {
    switch selectedTab {
    case .today:
      routePath.append(.tasksScope(.list(id)))
    case .tasks:
      tasksRoutePath.append(.tasksScope(.list(id)))
    case .calendar, .habits, .review:
      break
    }
  }

  public func applyPendingIntentHandoff() {
    guard let target = MobileIntentHandoff.consumeNavigationTarget() else { return }
    openNavigationTarget(target)
  }
}
