#if os(iOS)
import LorvexCore
@testable import LorvexWatch
import SwiftUI
import Testing

@Suite("Watch view snapshot tests")
@MainActor
struct LorvexWatchViewSnapshotTests {
  @Test
  func watchRootViewRendersCaptureSurface() {
    let store = LorvexWatchStore(core: try await makeSeededInMemoryCore())
    store.captureTitle = "Capture from wrist"

    let data = renderSnapshot(
      LorvexWatchRootView(store: store),
      size: CGSize(width: 198, height: 242)
    )

    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }
}

#endif
