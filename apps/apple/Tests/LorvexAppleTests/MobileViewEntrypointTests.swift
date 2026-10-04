import LorvexCore
@testable import LorvexMobile
import SwiftUI
import Testing

@MainActor
@Test
func mobileRootViewCanBeInstantiatedFromStore() async throws {
  // The store-backed root is the production mobile entry point on iOS and
  // iPadOS.
  _ = LorvexMobileStoreRootView(store: MobileStore(core: try await makeSeededInMemoryCore()))
}

@MainActor
@Test
func mobileSystemEntrypointModifierReturnsView() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore())
  _ = Text("mobile shell").lorvexMobileSystemEntrypoints(store: store)
}

@MainActor
@Test
func mobileTaskDetailSheetsUseNativePresentationChrome() throws {
  let source = try mobileSourceFile("Sources/LorvexMobile/MobileStoreTaskDetailView.swift")

  // The recurrence editor is a dense form, so it opens at full height.
  #expect(source.contains(".mobileFullEditorSheetPresentation()"))

  // Detents + drag indicator are standardized in the shared editor-presentation modifiers.
  let presentation = try mobileSourceFile("Sources/LorvexMobile/MobileEditorSheetPresentation.swift")
  #expect(presentation.contains(".presentationDetents([.medium, .large])"))
  #expect(presentation.contains(".presentationDetents([.large])"))
  #expect(presentation.contains(".presentationDragIndicator(.visible)"))
}

@MainActor
@Test
func mobileEditorSheetsTitleThemselvesInlineAndDenseFormsOpenFullHeight() throws {
  // A create or edit sheet carries its title inline between Cancel and the
  // confirm button, so a large title does not take a line of a short sheet.
  let sheets = [
    "MobileStoreCreateHabitSheet", "MobileStoreEditHabitSheet",
    "MobileStoreCreateListSheet", "MobileStoreEditListSheet",
    "MobileStoreCreateCalendarEventSheet", "MobileStoreEditCalendarEventSheet",
    "MobileStoreMemoryEditorSheet", "MobileTaskEditSheet",
  ]
  for name in sheets {
    let source = try mobileSourceFile("Sources/LorvexMobile/\(name).swift")
    #expect(source.contains(".navigationBarTitleDisplayMode(.inline)"), "\(name) titles itself inline")
  }

  // The forms with many fields (a habit, an event, a task) open at full height
  // instead of a half-height detent that hides most of them.
  let dense = [
    "MobileStoreCreateHabitSheet", "MobileStoreEditHabitSheet",
    "MobileStoreCreateCalendarEventSheet", "MobileStoreEditCalendarEventSheet",
    "MobileTaskEditSheet",
  ]
  for name in dense {
    let source = try mobileSourceFile("Sources/LorvexMobile/\(name).swift")
    #expect(source.contains(".mobileFullEditorSheetPresentation()"), "\(name) opens at full height")
  }
}

@MainActor
@Test
func mobileTodayShowsHabitsAndEventsOnlyWhenLoaded() throws {
  let source = try mobileSourceFile("Sources/LorvexMobile/MobileStoreTodayView.swift")
  let page = try mobileSourceFile("Sources/LorvexMobile/MobileTodayPage.swift")
  let schedule = try mobileSourceFile("Sources/LorvexMobile/MobileTodayScheduleSheet.swift")

  // Today never fabricates empty arrays: habits render only when their data is
  // loaded and, once the habits resting today are left out, non-empty, so a
  // clear day reads as one calm composed state rather than a stack of empty
  // sections.
  #expect(!page.contains("store.habits?.habits ?? []"))
  #expect(
    page.contains(
      "if let habits = store.habits?.habits.listed(on: store.logicalTodayString), !habits.isEmpty"))
  // The schedule list draws today's events and timed tasks as one timeline
  // (events filtered to the logical day, not the raw multi-day window), and
  // its empty line only when that timeline has nothing to draw.
  #expect(schedule.contains("let drawsRows = rows.contains { $0.kind != .now }"))
  #expect(schedule.contains("items: rows"))
  let calmState = try mobileSourceFile("Sources/LorvexMobile/MobileStoreTodayCalmState.swift")
  #expect(calmState.contains("calendarTimeline?.eventsOccurring(on: logicalTodayString)"))
  // Lists were intentionally removed from Today — they live in their own destination,
  // not as a feature-dump section here.
  #expect(!source.contains("store.lists"))
  #expect(!page.contains("store.lists"))
}

@MainActor
@Test
func mobileTodayUsesPullToRefreshAndLeavesCaptureToTheTabBar() throws {
  let source = try mobileSourceFile("Sources/LorvexMobile/MobileStoreTodayView.swift")

  #expect(source.contains(".refreshable { await store.refresh() }"))
  #expect(source.contains(".toolbar"))
  // On iPhone capture is the tab bar's round + on every tab, so Today's own
  // bar carries no second capture button.
  #expect(!source.contains(#""today.toolbar.capture""#))
  #expect(!source.contains(#""today.refresh""#))
  let root = try mobileSourceFile("Sources/LorvexMobile/LorvexMobileStoreRootView.swift")
  #expect(root.contains("Tab(value: MobileTabBarItem.capture, role: .search)"))
  #expect(root.contains("case .capture: store.isPresentingCapture = true"))
  #expect(root.contains(#""today.capture""#))
}

private func mobileSourceFile(_ relativePath: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let url = root.appendingPathComponent(relativePath)
  return try String(contentsOf: url, encoding: .utf8)
}
