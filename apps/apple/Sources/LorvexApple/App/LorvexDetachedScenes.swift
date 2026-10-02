import LorvexCore
import SwiftUI

@SceneBuilder
@MainActor
func lorvexDetachedScenes(store: AppStore) -> some Scene {
  WindowGroup(LorvexWindowID.detachedListTitle, for: LorvexList.ID.self) { $listID in
    DetachedListWindow(store: store, listID: listID)
      .lorvexClockLocale()
      .lorvexProductTimeZone(from: store)
  }
  .lorvexDefaultWindowPosition()

  WindowGroup(
    LorvexWindowID.stickyTaskTitle,
    id: LorvexWindowID.stickyTaskGroupID,
    for: StickyTaskRef.self
  ) { $ref in
    StickyTaskWindow(store: store, ref: ref)
      .lorvexClockLocale()
      .lorvexProductTimeZone(from: store)
  }
  .windowStyle(.hiddenTitleBar)
  .windowResizability(.contentSize)
  .lorvexDefaultWindowPosition()
}
