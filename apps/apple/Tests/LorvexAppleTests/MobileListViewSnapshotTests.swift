#if os(iOS)
  import LorvexCore
  import LorvexMobile
  import SwiftUI
  import Testing

  @testable import LorvexMobile

  @Suite("Mobile list view snapshot tests")
  @MainActor
  struct MobileListViewSnapshotTests {
    @Test
    func mobileEditListSheetRendersDraft() async {
      let store = MobileStore(core: try await makeSeededInMemoryCore())
      await store.refresh()
      await store.loadListDetail(id: LorvexPreviewSeedID.appleNativeList)
      let list = try? #require(store.selectedListDetail?.list)
      guard let list else {
        Issue.record("Expected seeded list")
        return
      }
      store.prepareListDraft(for: list)

      let data = renderSnapshot(
        MobileStoreEditListSheet(list: list, store: store, isPresented: .constant(true)),
        size: CGSize(width: 390, height: 520)
      )
      #expect(data != nil)
      #expect((data?.count ?? 0) > 1024)
    }
  }
#endif
