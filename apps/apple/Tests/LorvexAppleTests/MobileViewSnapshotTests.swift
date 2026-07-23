#if os(iOS)
import LorvexCore
import LorvexMobile
import SwiftUI
import Testing

@testable import LorvexMobile

@Suite("Mobile home snapshot tests")
@MainActor
struct MobileHomeSnapshotTests {

  @Test
  func mobileTodayViewRendersWithSeededSnapshot() {
    let snapshot = makeMobileHomeSnapshot()
    let data = renderSnapshot(
      MobileTodayView(snapshot: snapshot), size: CGSize(width: 390, height: 844))
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func mobileStoreTodayViewRendersPlanningSummaries() async {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    await store.refresh()
    let data = renderSnapshot(
      MobileStoreTodayView(store: store),
      size: CGSize(width: 390, height: 844)
    )
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func mobileStoreListDetailViewRendersLoadedList() async {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    await store.refresh()
    await store.loadListDetail(id: LorvexPreviewSeedID.appleNativeList)
    let data = renderSnapshot(
      MobileStoreListDetailView(listID: LorvexPreviewSeedID.appleNativeList, store: store),
      size: CGSize(width: 390, height: 844)
    )
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func mobileCreateListSheetRendersDraft() async {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    store.listDraft = MobileListDraft(name: "Mobile Writing", description: "Draft on iPad")
    let data = renderSnapshot(
      MobileStoreCreateListSheet(store: store, isPresented: .constant(true)),
      size: CGSize(width: 390, height: 600)
    )
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func mobileCreateHabitSheetRendersDraft() async {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    store.habitDraft = MobileHabitDraft(
      name: "Morning Review",
      cue: "After coffee",
      targetCountText: "2"
    )
    let data = renderSnapshot(
      MobileStoreCreateHabitSheet(store: store, isPresented: .constant(true)),
      size: CGSize(width: 390, height: 600)
    )
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func mobileFocusViewRendersWithEmptyFocusPlan() {
    let snapshot = makeMobileHomeSnapshot()
    let data = renderSnapshot(
      MobileFocusView(snapshot: snapshot), size: CGSize(width: 390, height: 844))
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func mobileFocusViewRendersWithActiveFocusPlan() {
    let snapshot = MobileHomeSnapshot(
      today: makeMobileHomeSnapshot().today,
      currentFocus: CurrentFocusPlan(
        date: "2026-05-24",
        taskIDs: ["snap-task-1"],
        briefing: "Start with the highest-priority task.",
        timezone: "UTC",
        localChangeSequence: 2
      ),
      weeklyReview: nil
    )
    let data = renderSnapshot(
      MobileFocusView(snapshot: snapshot), size: CGSize(width: 390, height: 844))
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

}

#endif
