import LorvexCore
@testable import LorvexMobile
import SwiftUI
import Testing

@MainActor
@Test
func mobileRootViewCanBeInstantiatedFromStore() async throws {
  // The store-backed root is the production mobile entry point on iOS,
  // iPadOS, and visionOS. The former snapshot-based view family
  // (LorvexMobileRootView / MobileTodayView / MobileFocusView /
  // MobileReviewView / MobileCaptureView / MobileRouteView) was removed —
  // every surface now binds to MobileStore.
  _ = LorvexMobileStoreRootView(store: MobileStore(core: try await makeSeededInMemoryCore()))
}

@MainActor
@Test
func spatialBackgroundModifierReturnsView() {
  _ = Text("hello").lorvexSpatialBackground()
}

@MainActor
@Test
func spatialContainerPaddingModifierReturnsView() {
  _ = Text("hello").lorvexSpatialContainerPadding()
}

@MainActor
@Test
func spatialModifiersComposeWithoutConflict() {
  _ = Text("hello")
    .lorvexSpatialBackground()
    .lorvexSpatialContainerPadding()
}

@MainActor
@Test
func bottomOrnamentModifierReturnsViewOnMacOS() {
  _ = Text("hello").lorvexBottomOrnament { Text("action") }
}

@MainActor
@Test
func bottomOrnamentModifierAcceptsVisibilityGate() {
  _ = Text("hello").lorvexBottomOrnament(isVisible: false) { Text("action") }
}

@MainActor
@Test
func bottomOrnamentModifierComposesWithSpatialModifiers() {
  _ = Text("content")
    .lorvexSpatialContainerPadding()
    .lorvexBottomOrnament { Button("Do it") {} }
}

@MainActor
@Test
func bottomOrnamentModifierAcceptsMultipleButtons() {
  _ = Text("base").lorvexBottomOrnament {
    HStack {
      Button("Complete") {}
      Button("Defer") {}
    }
  }
}

@MainActor
@Test
func mobileSystemEntrypointModifierReturnsView() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore())
  _ = Text("mobile shell").lorvexMobileSystemEntrypoints(store: store)
}

@MainActor
@Test
func mobileSheetsUseSpatialBackground() throws {
  let files = [
    // MobileStoreCalendarView is a thin Week/Day switch with no sheets of its
    // own; its event-create/edit sheets live in MobileCalendarDayView (below).
    "Sources/LorvexMobile/MobileCalendarDayView.swift",
    "Sources/LorvexMobile/MobileStoreDataImportSection.swift",
    "Sources/LorvexMobile/MobileDependencyField.swift",
    "Sources/LorvexMobile/MobileStoreHabitsView.swift",
    "Sources/LorvexMobile/MobileStoreListsView.swift",
    "Sources/LorvexMobile/MobileStoreMemoryView.swift",
    "Sources/LorvexMobile/MobileStoreListDetailView.swift",
    "Sources/LorvexMobile/MobileStoreTaskDetailView.swift",
    "Sources/LorvexMobile/MobileStoreTodayView.swift",
    "Sources/LorvexMobile/LorvexMobileStoreRootView.swift",
  ]

  for file in files {
    let source = try mobileSourceFile(file)
    #expect(
      source.contains(".sheet(") && source.contains(".lorvexSpatialBackground()"),
      "\(file) sheet roots should opt into the visionOS spatial background"
    )
  }
}

@MainActor
@Test
func mobileTaskDetailSheetsUseNativePresentationChrome() throws {
  let source = try mobileSourceFile("Sources/LorvexMobile/MobileStoreTaskDetailView.swift")

  #expect(source.contains(".mobileCompactEditorSheetPresentation()"))

  // Detents + drag indicator are standardized in the shared editor-presentation modifier.
  let presentation = try mobileSourceFile("Sources/LorvexMobile/MobileEditorSheetPresentation.swift")
  #expect(presentation.contains(".presentationDetents([.medium, .large])"))
  #expect(presentation.contains(".presentationDragIndicator(.visible)"))
}

@MainActor
@Test
func mobileTodayShowsHabitsAndEventsOnlyWhenLoaded() throws {
  let source = try mobileSourceFile("Sources/LorvexMobile/MobileStoreTodayView.swift")

  // Today never fabricates empty arrays: habits render only when their data is
  // loaded and non-empty, so a clear day reads as one calm composed state rather
  // than a stack of empty sections.
  #expect(!source.contains("store.habits?.habits ?? []"))
  #expect(source.contains("if let habits = store.habits?.habits, !habits.isEmpty"))
  // Today's events ride at the top as the Schedule agenda — filtered to today
  // (not the raw multi-day window) and shown only when there are events and no
  // focus timeline is folding them in.
  #expect(source.contains("private var showsStandaloneSchedule: Bool"))
  #expect(source.contains("!hasFocusTimeline && !todayEvents.isEmpty"))
  #expect(source.contains("if showsStandaloneSchedule"))
  #expect(source.contains("eventsOccurring(on: store.logicalTodayString)"))
  // Lists were intentionally removed from Today — they live in their own destination,
  // not as a feature-dump section here.
  #expect(!source.contains("store.lists"))
}

@MainActor
@Test
func mobileTodayUsesPullToRefreshAndKeepsBottomOrnamentFocusedOnCapture() throws {
  let source = try mobileSourceFile("Sources/LorvexMobile/MobileStoreTodayView.swift")

  #expect(source.contains(".refreshable { await store.refreshResettingCloudSyncPacing() }"))
  #expect(source.contains(#""today.capture""#))
  #expect(source.contains(".toolbar"))
  #expect(source.contains("horizontalSizeClass != .regular"))
  #expect(source.contains(#""today.toolbar.capture""#))
  #expect(!source.contains(#""today.refresh""#))
}

private func mobileSourceFile(_ relativePath: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let url = root.appendingPathComponent(relativePath)
  return try String(contentsOf: url, encoding: .utf8)
}
