import Foundation
import LorvexWidgetKitSupport
import Testing

@Test
func widgetFreshnessPolicyClassifiesAgeAndLabelsCompactly() {
  let policy = WidgetSnapshotFreshnessPolicy()
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let snapshot = WidgetSnapshot(
    generatedAt: "2023-11-14T19:43:20Z",
    timezone: "America/Los_Angeles",
    stats: .init(focusCount: 0, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    focusTasks: []
  )

  #expect(policy.classify(snapshot: snapshot, now: now) == .warning(ageSeconds: 9_000))
  #expect(policy.compactAgeLabel(ageSeconds: 5 * 60) == "5m ago")
  #expect(policy.compactAgeLabel(ageSeconds: 3 * 60 * 60) == "3h ago")
  #expect(policy.compactAgeLabel(ageSeconds: 2 * 24 * 60 * 60) == "2d ago")
}

@Test
func widgetFreshnessPolicyExpiresCurrentDayMaterialAtProductMidnight() throws {
  let policy = WidgetSnapshotFreshnessPolicy()
  let now = try #require(ISO8601DateFormatter().date(from: "2026-05-23T07:45:00Z"))
  var newYork = calendar(inZone: "America/New_York")
  newYork.locale = Locale(identifier: "en_US_POSIX")

  // The payload was materialized on May 22 in Los Angeles. Seventy-five real
  // minutes later, the product timezone itself has crossed midnight. The
  // injected New York calendar must not alter that authoritative boundary.
  let currentPayload = WidgetSnapshot(
    generatedAt: "2026-05-23T06:30:00Z",
    timezone: "America/Los_Angeles",
    logicalDay: "2026-05-22",
    stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 1),
    briefing: nil,
    focusTasks: []
  )
  let legacyPayload = WidgetSnapshot(
    generatedAt: "2026-05-23T06:30:00Z",
    timezone: "America/Los_Angeles",
    stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 1),
    briefing: nil,
    focusTasks: []
  )

  for snapshot in [currentPayload, legacyPayload] {
    let result = policy.validatingCurrentDay(
      .snapshot(snapshot),
      now: now,
      calendar: newYork
    )
    guard case .fallback(let fallback) = result else {
      Issue.record("Expected the old logical day to expire after travel")
      continue
    }
    #expect(fallback.reason == .expiredDay)
  }
}

@Test
func widgetTimelineRefreshPolicyTracksVisibleAgeChangesWithoutStalePolling() {
  let policy = WidgetTimelineRefreshPolicy()

  // Fresh content waits exactly until the two-hour warning boundary.
  #expect(policy.refreshIntervalSeconds(freshness: .fresh(ageSeconds: 60)) == 119 * 60)
  // Warning labels are hour-granular, so the next visible change is one hour away.
  #expect(policy.refreshIntervalSeconds(freshness: .warning(ageSeconds: 3 * 60 * 60)) == 60 * 60)
  // A 26-hour-old snapshot reads "1d ago" until the 48-hour boundary.
  #expect(policy.refreshIntervalSeconds(freshness: .stale(ageSeconds: 26 * 60 * 60)) == 22 * 60 * 60)
  // Missing/unparseable data cannot become fresher from polling the same file;
  // app-published WidgetCenter reloads remain the primary update path.
  #expect(policy.refreshIntervalSeconds(freshness: nil) == 24 * 60 * 60)
  #expect(policy.refreshIntervalSeconds(freshness: .unknownTimestamp) == 24 * 60 * 60)
}

@Test
func widgetTimelineRefreshPolicyHonorsWidgetKitFiveMinuteFloorNearBoundaries() {
  let policy = WidgetTimelineRefreshPolicy()

  #expect(
    policy.refreshIntervalSeconds(freshness: .fresh(ageSeconds: 2 * 60 * 60 - 10))
      == WidgetTimelineRefreshPolicy.minimumIntervalSeconds)
  #expect(
    policy.refreshIntervalSeconds(freshness: .warning(ageSeconds: 24 * 60 * 60 - 10))
      == WidgetTimelineRefreshPolicy.minimumIntervalSeconds)
}

@Test
func widgetTimelineRefreshPolicyTracksCustomMinuteScaleFreshnessLabels() {
  let policy = WidgetTimelineRefreshPolicy()
  let freshnessPolicy = WidgetSnapshotFreshnessPolicy(
    warningAfterSeconds: 5 * 60,
    staleAfterSeconds: 30 * 60
  )

  #expect(
    policy.refreshIntervalSeconds(
      freshness: .warning(ageSeconds: 12 * 60),
      freshnessPolicy: freshnessPolicy
    ) == WidgetTimelineRefreshPolicy.minimumIntervalSeconds)
  #expect(
    policy.refreshIntervalSeconds(
      freshness: .stale(ageSeconds: 45 * 60),
      freshnessPolicy: freshnessPolicy
    ) == WidgetTimelineRefreshPolicy.minimumIntervalSeconds)
}

/// A calendar pinned to a fixed time zone, so the next-midnight math is
/// deterministic regardless of where the test runs.
private func calendar(inZone identifier: String) -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: identifier)!
  return calendar
}

@Test
func widgetPolicyComputesNextLocalMidnightInTheUsersZone() {
  let policy = WidgetTimelineRefreshPolicy()
  let tokyo = calendar(inZone: "Asia/Tokyo")

  // 2026-05-22 20:30:00 JST → the next local midnight is 2026-05-23 00:00 JST.
  var components = DateComponents()
  components.year = 2026
  components.month = 5
  components.day = 22
  components.hour = 20
  components.minute = 30
  let now = tokyo.date(from: components)!

  let midnight = policy.nextLocalMidnight(after: now, calendar: tokyo)

  let midnightComponents = tokyo.dateComponents([.year, .month, .day, .hour, .minute], from: midnight)
  #expect(midnightComponents.year == 2026)
  #expect(midnightComponents.month == 5)
  #expect(midnightComponents.day == 23)
  #expect(midnightComponents.hour == 0)
  #expect(midnightComponents.minute == 0)
  // Strictly after `now`, and it is the start of the following local day.
  #expect(midnight > now)
  #expect(midnight == tokyo.startOfDay(for: now.addingTimeInterval(24 * 60 * 60)))
}

@Test
func widgetPolicyRefreshDateClampsToMidnightWhenItComesBeforeTheAgeInterval() {
  let policy = WidgetTimelineRefreshPolicy()
  let utc = calendar(inZone: "UTC")

  // 23:45 UTC, snapshot fresh → age-based refresh would be 01:45 next day, but
  // the day boundary (00:00) comes first, so the reload is scheduled at midnight.
  var components = DateComponents()
  components.year = 2026
  components.month = 5
  components.day = 22
  components.hour = 23
  components.minute = 45
  let now = utc.date(from: components)!

  let refresh = policy.nextRefreshDate(
    after: now, freshness: .fresh(ageSeconds: 0), calendar: utc)

  #expect(refresh == policy.nextLocalMidnight(after: now, calendar: utc))
  #expect(refresh == utc.startOfDay(for: now.addingTimeInterval(24 * 60 * 60)))
  // The plain two-hour age interval would have overshot midnight.
  #expect(refresh < now.addingTimeInterval(2 * 60 * 60))
}

@Test
func widgetPolicyRefreshDateUsesAgeIntervalWhenMidnightIsFarOff() {
  let policy = WidgetTimelineRefreshPolicy()
  let utc = calendar(inZone: "UTC")

  // Mid-morning: the next midnight is many hours away, so the freshness-based
  // interval wins and the day-boundary clamp is a no-op.
  var components = DateComponents()
  components.year = 2026
  components.month = 5
  components.day = 22
  components.hour = 9
  components.minute = 0
  let now = utc.date(from: components)!

  let refresh = policy.nextRefreshDate(
    after: now, freshness: .fresh(ageSeconds: 0), calendar: utc)

  #expect(refresh == now.addingTimeInterval(2 * 60 * 60))
}
