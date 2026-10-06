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
  /// URL reaches ``navigate(to:)`` regardless of which surface delivered it.
  public func openDeepLink(_ url: URL) {
    guard let route = LorvexDeepLinkRoute(url: url) else { return }
    navigate(to: route)
  }

  /// Applies a Home Screen / Dock quick action to the running mobile UI.
  ///
  /// `.quickCapture` presents the capture sheet immediately — matching the
  /// action's label and the macOS Quick Capture window — rather than merely
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

  /// Lands on `target`: selects its tab and replaces every tab's stack, the
  /// selected tab's with the target's screens and the others with their roots,
  /// so a jump (deep link, Handoff, intent) never surfaces a stale pushed
  /// screen. A task or habit on the path also becomes the selection, which a
  /// regular-width workspace shows in its detail pane.
  public func openNavigationTarget(_ target: MobileNavigationTarget) {
    selectedTab = target.selectedTab
    routePath = target.selectedTab == .today ? target.path : []
    calendarRoutePath = target.selectedTab == .calendar ? target.path : []
    tasksRoutePath = target.selectedTab == .tasks ? target.path : []
    reviewRoutePath = target.selectedTab == .review ? target.path : []
    for route in target.path {
      switch route {
      case .task(let id): selectedTaskID = id
      case .habit(let id): selectedHabitID = id
      default: break
      }
    }
  }

  /// Opens a destination. Tab destinations select their tab (Lists is the
  /// Tasks home itself). Habits, Memory, and Settings are secondary workspaces
  /// pushed onto their hosting tab's stack (Habits and Memory on Tasks, where
  /// the Tasks home's rows lead; Settings on Today).
  public func openWorkspaceDestination(_ destination: MobileDestination) {
    switch destination {
    case .tasks, .lists:
      openPrimaryShortcutTab(.tasks)
    case .calendar:
      openPrimaryShortcutTab(.calendar)
    case .review:
      openPrimaryShortcutTab(.review)
    case .habits, .memory:
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
    case .calendar, .review:
      break
    }
  }

  /// Applies the one request a system intent left for the app: a quick action
  /// (the Quick Capture control presents the capture sheet), a task, or a
  /// destination.
  public func applyPendingIntentHandoff() {
    if let action = MobileIntentHandoff.consumeQuickAction() {
      performQuickAction(action)
      return
    }
    guard let target = MobileIntentHandoff.consumeNavigationTarget() else { return }
    openNavigationTarget(target)
  }
}
