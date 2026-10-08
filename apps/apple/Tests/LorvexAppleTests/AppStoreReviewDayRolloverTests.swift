import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// The product time zone moves the logical day without moving the real clock:
/// Pacific/Pago_Pago is 25 hours behind Pacific/Kiritimati, so at any instant
/// the second zone's calendar day is one or two days after the first's.
private let earlierProductZone = "Pacific/Pago_Pago"
private let laterProductZone = "Pacific/Kiritimati"

private func rolloverYmdAddingDays(_ day: String, _ days: Int) -> String {
  LorvexDateFormatters.ymdUTCAddingDays(day, days: days) ?? day
}

/// A store whose logical day is the earlier zone's, refreshed once, plus the
/// preferences suite name to remove afterwards.
@MainActor
private func makeRolloverStore() async throws -> (
  store: AppStore, core: SwiftLorvexCoreService, suite: String
) {
  let suite = "AppStoreReviewDayRollover.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defaults.removePersistentDomain(forName: suite)
  let core = try makeInMemoryCore()
  _ = try await core.setPreference(key: "timezone", value: earlierProductZone)
  let store = AppStore(core: core, defaults: defaults)
  await store.refresh()
  return (store, core, suite)
}

/// Moves the logical day forward and lets the store see it, as the refresh at
/// midnight does.
@MainActor
private func rollToTheNextDay(_ store: AppStore, _ core: SwiftLorvexCoreService) async throws {
  _ = try await core.setPreference(key: "timezone", value: laterProductZone)
  await store.refresh()
}

/// Choosing today in the date strip, or pressing Today, goes back to following
/// today. A Mac app stays open for days, so a pinned copy of that day would keep
/// the Day scope on a day that has ended.
@MainActor
@Test
func appStoreReviewDayChosenAsTodayFollowsTheLogicalDay() async throws {
  let (store, core, suite) = try await makeRolloverStore()
  defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
  let firstDay = store.logicalTodayDateString
  await store.selectReviewDay(rolloverYmdAddingDays(firstDay, -1))
  await store.selectReviewDay(firstDay)
  #expect(store.selectedReviewDate == firstDay)

  try await rollToTheNextDay(store, core)

  #expect(store.logicalTodayDateString > firstDay)
  #expect(store.selectedReviewDate == store.logicalTodayDateString)
  #expect(store.isViewingCurrentDay)
}

/// A day the user opened on purpose stays open when the clock passes midnight.
@MainActor
@Test
func appStoreReviewDayStaysOnAPastDayTheUserChose() async throws {
  let (store, core, suite) = try await makeRolloverStore()
  defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
  let pastDay = rolloverYmdAddingDays(store.logicalTodayDateString, -2)
  await store.selectReviewDay(pastDay)

  try await rollToTheNextDay(store, core)

  #expect(store.selectedReviewDate == pastDay)
}

/// Text typed on the last day and not yet saved is written to that day before
/// the logical day moves, so it is not attached to the new day by an autosave
/// that fires after midnight.
@MainActor
@Test
func appStoreSavesAnUnsavedReviewToItsOwnDayWhenTheDayRollsOver() async throws {
  let (store, core, suite) = try await makeRolloverStore()
  defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
  let firstDay = store.logicalTodayDateString
  store.dailyReviewSummaryDraft = "Typed just before midnight"

  try await rollToTheNextDay(store, core)

  let saved = try await core.loadDailyReview(date: firstDay)
  #expect(saved?.summary == "Typed just before midnight")
  #expect(store.dailyReviewSummaryDraft.isEmpty)
  let newDay = try await core.loadDailyReview(date: store.selectedReviewDate)
  #expect(newDay == nil)
}
