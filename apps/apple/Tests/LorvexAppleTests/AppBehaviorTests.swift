import Foundation
import LorvexCore
import Testing
import LorvexCloudSync

@testable import LorvexApple

// App-layer behavioral unit tests: exercised through real types (AppStore,
// SettingsPermissionsSection, calendar helpers) rather than by scanning source.
// Source-shape / UI-polish invariants that used to live here now run as a
// repository-hygiene gate (script/verify_source_hygiene.py), so the Apple test
// suite never walks source trees.

@Test
@MainActor
func permissionStatusNotDeterminedIsAOneWayDoor() {
  // A fresh read starts from unknown/notDetermined and is taken as-is.
  #expect(SettingsPermissionsSection.resolve(read: .notDetermined, current: .unknown) == .notDetermined)
  #expect(SettingsPermissionsSection.resolve(read: .authorized, current: .notDetermined) == .authorized)
  #expect(SettingsPermissionsSection.resolve(read: .denied, current: .notDetermined) == .denied)

  // A stale `notDetermined` read after a permission was already decided (the
  // EventKit/notification process cache bug) must NOT reset the row — granting
  // one permission must not flip a sibling back to "Not Set".
  #expect(SettingsPermissionsSection.resolve(read: .notDetermined, current: .authorized) == .authorized)
  #expect(SettingsPermissionsSection.resolve(read: .notDetermined, current: .denied) == .denied)
  #expect(SettingsPermissionsSection.resolve(read: .notDetermined, current: .writeOnly) == .writeOnly)

  // A real status change away from notDetermined is still honored.
  #expect(SettingsPermissionsSection.resolve(read: .denied, current: .authorized) == .denied)
  #expect(SettingsPermissionsSection.resolve(read: .writeOnly, current: .authorized) == .writeOnly)
}

@MainActor
@Test
func appStoreToastMessageStartsNil() throws {
  let store = AppStore(core: try makeInMemoryCore())
  #expect(store.toastMessage == nil)
}

@MainActor
@Test
func appStoreToastMessageCanBeSetAndCleared() throws {
  let store = AppStore(core: try makeInMemoryCore())
  store.toastMessage = "Something went wrong."
  #expect(store.toastMessage == "Something went wrong.")
  store.toastMessage = nil
  #expect(store.toastMessage == nil)
}

@MainActor
@Test
func appStoreToastMessageIsIndependentOfErrorMessage() throws {
  let store = AppStore(core: try makeInMemoryCore())
  store.errorMessage = "Blocking error"
  store.toastMessage = "Transient warning"
  #expect(store.errorMessage == "Blocking error")
  #expect(store.toastMessage == "Transient warning")
  store.errorMessage = nil
  #expect(store.toastMessage == "Transient warning")
}

@MainActor
@Test
func moveHabitsPermutesVisibleOrderViaSyncedCore() async throws {
  let defaults = UserDefaults(suiteName: "test.moveHabits")!
  defaults.removePersistentDomain(forName: "test.moveHabits")
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  await store.refresh()
  let original = store.filteredHabits.map(\.id)
  guard original.count >= 2 else { return }

  // Drag the first habit two slots down. The new order is persisted through the
  // core `position` column (no UserDefaults) and reflected back on refresh.
  await store.moveHabits(fromOffsets: IndexSet([0]), toOffset: 2)
  let reordered = store.filteredHabits.map(\.id)
  #expect(reordered != original)
  #expect(Set(reordered) == Set(original))
  #expect(reordered.first == original[1])
}

@MainActor
@Test
func reorderListsPermutesCatalogOrderViaSyncedCore() async throws {
  let defaults = UserDefaults(suiteName: "test.reorderLists")!
  defaults.removePersistentDomain(forName: "test.reorderLists")
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  await store.refresh()
  let original = store.orderedLists.map(\.id)
  guard original.count >= 2 else { return }

  let moved = Array(original.reversed())
  await store.reorderLists(moved)
  #expect(store.orderedLists.map(\.id) == moved)
}

@MainActor
@Test
func mergeReorderedVisibleListsPreservesHiddenOrderSlots() {
  let merged = AppStore.mergeReorderedVisible(
    ["c", "a"],
    intoFullOrder: ["a", "b", "c", "d"]
  )

  #expect(merged == ["c", "b", "a", "d"])
}

@MainActor
@Test
func calendarDateRangeHelperShiftsAnchorCorrectly() {
  var components = DateComponents()
  components.calendar = Calendar(identifier: .gregorian)
  components.year = 2026
  components.month = 1
  components.day = 10
  components.timeZone = TimeZone.current
  let anchor = components.date!

  let from = AppStore.ymdFormatter.string(from: anchor)
  let to = AppStore.dateString(days: 14, from: anchor)
  #expect(from == "2026-01-10")
  #expect(to == "2026-01-24")
}

@MainActor
@Test
func calendarDateRangeHelperMonthBoundary() {
  var components = DateComponents()
  components.calendar = Calendar(identifier: .gregorian)
  components.year = 2026
  components.month = 1
  components.day = 25
  components.timeZone = TimeZone.current
  let anchor = components.date!

  let to = AppStore.dateString(days: 14, from: anchor)
  #expect(to == "2026-02-08")
}

@Test @MainActor
func macOSDailyReviewAutosavePersistsAndManualFlushDoesNotDoubleWrite() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  // A fresh edit to today's review is unsaved.
  store.dailyReviewSummaryDraft = "Shipped the settings polish"
  #expect(!store.dailyReviewDraftMatchesLoaded)

  // Autosave (the debounced task) persists the edit …
  await store.saveDailyReviewDraft()
  #expect(store.dailyReview?.summary == "Shipped the settings polish")
  #expect(store.dailyReviewDraftMatchesLoaded)

  // … and a manual Save racing that just-fired autosave is a guarded no-op: the
  // draft already matches the loaded review, so flush never writes a second time.
  await store.flushDailyReviewDraftIfNeeded()
  #expect(store.dailyReview?.summary == "Shipped the settings polish")
  #expect(store.dailyReviewDraftMatchesLoaded)
}
