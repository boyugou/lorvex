#if os(iOS)
import LorvexCore
import LorvexMobile
import SwiftUI
import Testing

@testable import LorvexMobile

@Suite("Mobile capture and review snapshot tests")
@MainActor
struct MobileCaptureReviewViewSnapshotTests {

  @Test
  func mobileStoreReviewViewRendersMemorySection() async {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    await store.refresh()
    await store.loadMemorySnapshot()
    let data = renderSnapshot(
      MobileStoreReviewView(store: store),
      size: CGSize(width: 390, height: 844)
    )
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func mobileStoreReviewViewRendersDataExportSection() async {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    await store.refresh()
    let data = renderSnapshot(
      MobileStoreReviewView(store: store),
      size: CGSize(width: 390, height: 844)
    )
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func mobileStoreReviewViewRendersDiagnostics() async {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    await store.refresh()
    await store.loadRuntimeDiagnostics()
    let data = renderSnapshot(
      MobileStoreReviewView(store: store),
      size: CGSize(width: 390, height: 900)
    )
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

}

#endif
