import LorvexCore
import SwiftUI

@SceneBuilder
@MainActor
func lorvexDetachedScenes(store: AppStore) -> some Scene {
  WindowGroup(LorvexWindowID.detachedListTitle, for: LorvexList.ID.self) { $listID in
    DetachedListWindow(store: store, listID: listID)
  }
  .lorvexDefaultWindowPosition()

  WindowGroup(
    LorvexWindowID.stickyTaskTitle,
    id: LorvexWindowID.stickyTaskGroupID,
    for: StickyTaskRef.self
  ) { $ref in
    StickyTaskWindow(store: store, ref: ref)
  }
  .windowStyle(.hiddenTitleBar)
  .windowResizability(.contentSize)
  .lorvexDefaultWindowPosition()
}
