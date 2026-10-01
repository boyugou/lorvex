import LorvexCore
import SwiftUI

struct WorkspaceView: View {
  @Bindable var store: AppStore

  var body: some View {
    workspace
      // The detail column needs one size anchor that does not depend on which
      // workspace is showing. The workspaces disagree about whether they claim
      // the pane — some fill it, some size to their content — so without this
      // frame the column's content size changes on every selection change and
      // the split view re-measures both columns, which reads as the sidebar
      // jumping. `topLeading` keeps a workspace that does not fill anchored
      // where an unfilled pane child already sits.
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      // One search field for the window, above the workspace switch, so
      // moving between All Tasks and Memory keeps the same toolbar item.
      .lorvexWorkspaceSearchField(store: store, selection: store.selection)
  }

  @ViewBuilder
  private var workspace: some View {
    switch store.selection {
    case .today:
      TodayView(store: store)
    case .tasks:
      TasksView(store: store)
    case .lists:
      ListsWorkspaceView(store: store)
    case .calendar:
      CalendarWorkspaceView(store: store)
    case .habits:
      HabitsWorkspaceView(store: store)
    case .reviews:
      ReviewsWorkspaceView(store: store)
    case .memory:
      MemoryWorkspaceView(store: store)
    }
  }
}

