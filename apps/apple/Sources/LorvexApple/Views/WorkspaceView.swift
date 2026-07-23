import LorvexCore
import SwiftUI

struct WorkspaceView: View {
  @Bindable var store: AppStore

  var body: some View {
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

