#if os(iOS)
  import CoreGraphics
  import LorvexCore
  import SwiftUI
  import Testing

  @testable import LorvexMobile

  @Suite("Mobile habit view snapshot tests")
  @MainActor
  struct MobileHabitViewSnapshotTests {
    @Test
    func mobileEditHabitSheetRendersDraft() async throws {
      let store = MobileStore(core: try await makeSeededInMemoryCore())
      await store.refresh()
      let habit = try #require(store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })
      store.prepareHabitDraft(for: habit)

      let data = renderSnapshot(
        MobileStoreEditHabitSheet(habit: habit, store: store, isPresented: .constant(true)),
        size: CGSize(width: 390, height: 600)
      )

      #expect(data != nil)
      #expect((data?.count ?? 0) > 1024)
    }
  }
#endif
