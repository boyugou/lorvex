import SwiftUI

struct LorvexWorkspaceWindowView: View {
  let windowID: LorvexWindowID
  let store: AppStore

  var body: some View {
    content
      .lorvexRefreshableWindow(windowID, store: store)
      .tint(.accentColor)
      .focusedSceneValue(\.lorvexTaskCommandContext, taskCommandContext)
      .lorvexRecurringCancelDialog(store)
      .lorvexPermanentDeleteDialog(store)
      // Standalone workspace windows present their own surface, so a failed
      // core mutation here would otherwise drop silently (rule 5). ContentView
      // and the detached task/list windows already mount this alert.
      .lorvexErrorAlert(store)
  }

  private var taskCommandContext: LorvexTaskCommandContext? {
    switch windowID {
    case .today:
      LorvexTaskCommandContext(store: store, selectionSurface: .focus)
    case .tasks:
      LorvexTaskCommandContext(store: store, selectionSurface: .taskWorkspace)
    case .taskDetail:
      LorvexTaskCommandContext(store: store, selectionSurface: nil)
    case .main, .calendar, .lists, .habits, .reviews:
      nil
    }
  }

  @ViewBuilder
  private var content: some View {
    switch windowID {
    case .today:
      TodayView(store: store)
    case .tasks:
      TasksView(store: store)
    case .calendar:
      CalendarWorkspaceView(store: store)
    case .lists:
      ListsWorkspaceView(store: store)
    case .habits:
      HabitsWorkspaceView(store: store)
    case .reviews:
      ReviewsWorkspaceView(store: store)
    case .taskDetail:
      TaskDetailView(store: store)
    case .main:
      EmptyView()
    }
  }
}
