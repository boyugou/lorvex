import SwiftUI

@SceneBuilder
@MainActor
func lorvexWorkspaceScenes(store: AppStore) -> some Scene {
  Window(LorvexWindowID.today.title, id: LorvexWindowID.today.rawValue) {
    LorvexWorkspaceWindowView(windowID: .today, store: store)
  }
  .lorvexDefaultWindowPosition()

  Window(LorvexWindowID.tasks.title, id: LorvexWindowID.tasks.rawValue) {
    LorvexWorkspaceWindowView(windowID: .tasks, store: store)
  }
  .lorvexDefaultWindowPosition()

  Window(LorvexWindowID.calendar.title, id: LorvexWindowID.calendar.rawValue) {
    LorvexWorkspaceWindowView(windowID: .calendar, store: store)
  }
  .lorvexDefaultWindowPosition()

  Window(LorvexWindowID.lists.title, id: LorvexWindowID.lists.rawValue) {
    LorvexWorkspaceWindowView(windowID: .lists, store: store)
  }
  .lorvexDefaultWindowPosition()

  Window(LorvexWindowID.habits.title, id: LorvexWindowID.habits.rawValue) {
    LorvexWorkspaceWindowView(windowID: .habits, store: store)
  }
  .lorvexDefaultWindowPosition()

  Window(LorvexWindowID.reviews.title, id: LorvexWindowID.reviews.rawValue) {
    LorvexWorkspaceWindowView(windowID: .reviews, store: store)
  }
  .lorvexDefaultWindowPosition()

  Window(LorvexWindowID.taskDetail.title, id: LorvexWindowID.taskDetail.rawValue) {
    LorvexWorkspaceWindowView(windowID: .taskDetail, store: store)
  }
  .lorvexDefaultWindowPosition()
}
