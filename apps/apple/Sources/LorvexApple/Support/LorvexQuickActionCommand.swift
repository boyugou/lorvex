import Foundation
import LorvexCore

extension LorvexQuickAction {
  var commandAction: MainToolbarCommandAction {
    switch self {
    case .quickCapture:
      .appCommand(.focusQuickAdd)
    case .openToday:
      .openWindow(.today)
    }
  }

  var dockFallbackDeepLink: URL {
    switch commandAction {
    case .appCommand(.focusQuickAdd):
      deepLinkURL
    case .appCommand(.refreshStore):
      // No deep-link surface for a refresh from the Dock — route the user to
      // Today so the action's effect is visible.
      LorvexDeepLinkRoute.destination(.today).url
    case .openWindow(let windowID):
      LorvexDeepLinkRoute.destination(windowID.sidebarSelectionFallback).url
    }
  }
}

private extension LorvexWindowID {
  var sidebarSelectionFallback: SidebarSelection {
    switch self {
    case .main, .today:
      .today
    case .tasks, .taskDetail:
      .tasks
    case .calendar:
      .calendar
    case .lists:
      .lists
    case .habits:
      .habits
    case .reviews:
      .reviews
    }
  }
}
