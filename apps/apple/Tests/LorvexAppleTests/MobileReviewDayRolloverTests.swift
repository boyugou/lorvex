import Foundation
import LorvexCore
import LorvexMobile
import Testing

private func rolloverYmdAddingDays(_ day: String, _ days: Int) -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  formatter.dateFormat = "yyyy-MM-dd"
  let base = formatter.date(from: day)!
  let shifted = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: base)!
  return formatter.string(from: shifted)
}

/// The product time zone moves the logical day without moving the real clock:
/// Pacific/Pago_Pago is 25 hours behind Pacific/Kiritimati, so at any instant
/// the second zone's calendar day is one or two days after the first's.
private let earlierProductZone = "Pacific/Pago_Pago"
private let laterProductZone = "Pacific/Kiritimati"

/// A store whose logical day is the earlier zone's, refreshed once.
@MainActor
private func makeRolloverStore() async throws -> (store: MobileStore, core: SwiftLorvexCoreService) {
  let core = try makeInMemoryCore()
  _ = try await core.setPreference(key: "timezone", value: earlierProductZone)
  let store = MobileStore(core: core)
  await store.refresh()
  return (store, core)
}

/// Moves the logical day forward and lets the store see it, as the refresh at
/// midnight does.
@MainActor
private func rollToTheNextDay(_ store: MobileStore, _ core: SwiftLorvexCoreService) async throws {
  _ = try await core.setPreference(key: "timezone", value: laterProductZone)
  await store.refresh()
}

/// The Day review opens on today. A phone keeps the app alive overnight, so the
/// refresh that sees the new day must carry a review that was showing today to
/// the new today; otherwise the page shows yesterday as read-only each morning.
@MainActor
@Test
func mobileStoreReviewDayFollowsTheLogicalDayAcrossMidnight() async throws {
  let (store, core) = try await makeRolloverStore()
  let firstDay = store.logicalTodayString
  #expect(store.selectedReviewDate == firstDay)

  try await rollToTheNextDay(store, core)

  let secondDay = store.logicalTodayString
  #expect(secondDay > firstDay)
  #expect(store.selectedReviewDate == secondDay)
  #expect(store.selectedReviewDayIsEditable)
}

/// A day the user opened on purpose stays open when the clock passes midnight.
@MainActor
@Test
func mobileStoreReviewDayStaysOnAPastDayTheUserChose() async throws {
  let (store, core) = try await makeRolloverStore()
  let pastDay = rolloverYmdAddingDays(store.logicalTodayString, -2)
  await store.selectReviewDay(pastDay)

  try await rollToTheNextDay(store, core)

  #expect(store.selectedReviewDate == pastDay)
}

/// Text typed on the last day and not yet saved is written to that day before
/// the page moves on, so it is neither lost nor attached to the new day.
@MainActor
@Test
func mobileStoreSavesAnUnsavedReviewToItsOwnDayWhenTheDayRollsOver() async throws {
  let (store, core) = try await makeRolloverStore()
  let firstDay = store.logicalTodayString
  await store.loadDailyReviewDraft()
  store.dailyReviewDraft.summary = "Typed just before midnight"

  try await rollToTheNextDay(store, core)

  let saved = try await core.loadDailyReview(date: firstDay)
  #expect(saved?.summary == "Typed just before midnight")
  #expect(store.selectedReviewDate == store.logicalTodayString)
  #expect(store.dailyReviewDraft.summary.isEmpty)
  let newDay = try await core.loadDailyReview(date: store.selectedReviewDate)
  #expect(newDay == nil)
}
