import Foundation
import LorvexCore
import Testing

private func task(due: Date?, status: LorvexTask.Status = .open) -> LorvexTask {
  LorvexTask(
    id: "t", title: "T", notes: "", priority: .p2, status: status,
    dueDate: due, estimatedMinutes: nil, tags: []
  )
}

private let cal = Calendar(identifier: .gregorian)

/// A due date earlier today is still "not overdue" — overdue is day-granular,
/// so a task due at 9am is not past due at 5pm the same day.
@Test
func dueIsOverdueIsDayGranular() {
  let now = Date(timeIntervalSince1970: 1_780_000_000)  // some afternoon
  let earlierToday = now.addingTimeInterval(-3 * 3600)
  let yesterday = now.addingTimeInterval(-26 * 3600)
  let tomorrow = now.addingTimeInterval(26 * 3600)

  #expect(task(due: earlierToday).isOverdue(now: now, timeZone: cal.timeZone) == false)
  #expect(task(due: yesterday).isOverdue(now: now, timeZone: cal.timeZone) == true)
  #expect(task(due: tomorrow).isOverdue(now: now, timeZone: cal.timeZone) == false)
  #expect(task(due: nil).isOverdue(now: now, timeZone: cal.timeZone) == false)
}

/// Only unresolved work is overdue: a finished or cancelled task keeps its past
/// due date but never reads as a missed deadline, while a started or parked one
/// still does.
@Test
func resolvedTasksAreNeverOverdue() {
  let now = Date(timeIntervalSince1970: 1_780_000_000)
  let yesterday = now.addingTimeInterval(-26 * 3600)

  #expect(task(due: yesterday, status: .completed).isOverdue(now: now, timeZone: cal.timeZone) == false)
  #expect(task(due: yesterday, status: .cancelled).isOverdue(now: now, timeZone: cal.timeZone) == false)
  #expect(task(due: yesterday, status: .inProgress).isOverdue(now: now, timeZone: cal.timeZone) == true)
  #expect(task(due: yesterday, status: .someday).isOverdue(now: now, timeZone: cal.timeZone) == true)
}

/// The relative label is present exactly when the task has a due date.
@Test
func dueRelativeLabelPresenceFollowsDueDate() {
  let now = Date(timeIntervalSince1970: 1_780_000_000)
  #expect(task(due: nil).cachedDueRelativeLabel(now: now, timeZone: cal.timeZone) == nil)
  #expect(task(due: now).cachedDueRelativeLabel(now: now, timeZone: cal.timeZone) != nil)
}

/// Due today reads "today", never "now", and the neighbours read by the day:
/// the label counts whole days, whatever the hour of either instant.
@Test
func dueRelativeLabelCountsWholeDays() {
  let now = Date(timeIntervalSince1970: 1_780_000_000)
  let formatter = RelativeDateTimeFormatter()
  formatter.dateTimeStyle = .named
  formatter.unitsStyle = .abbreviated
  func day(_ offset: Int) -> String { formatter.localizedString(from: DateComponents(day: offset)) }
  #expect(task(due: now).cachedDueRelativeLabel(now: now, timeZone: cal.timeZone) == day(0))
  #expect(task(due: now.addingTimeInterval(-3 * 3600)).cachedDueRelativeLabel(now: now, timeZone: cal.timeZone) == day(0))
  #expect(task(due: now.addingTimeInterval(26 * 3600)).cachedDueRelativeLabel(now: now, timeZone: cal.timeZone) == day(1))
  #expect(task(due: now.addingTimeInterval(-26 * 3600)).cachedDueRelativeLabel(now: now, timeZone: cal.timeZone) == day(-1))
  #expect(task(due: now).cachedDueRelativeLabel(now: now, timeZone: cal.timeZone) != formatter.localizedString(for: now, relativeTo: now))
}

/// Production planned dates materialize the stored day string at UTC midnight
/// (`LorvexDateFormatters.ymdUTC`). In any timezone west of UTC, taking the
/// LOCAL start-of-day of that instant lands on the previous day — a task
/// planned "today" rendered "yesterday" and counted overdue the moment it was
/// created. The due day must be read in UTC and only then compared to the
/// user's local today.
@Test
func utcMidnightDueDateReadsAsItsOwnDayWestOfUTC() throws {
  var losAngeles = Calendar(identifier: .gregorian)
  losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

  let storedToday = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-06-10"))
  let storedYesterday = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-06-09"))
  var comps = DateComponents()
  comps.year = 2026
  comps.month = 6
  comps.day = 10
  comps.hour = 11
  let now = try #require(losAngeles.date(from: comps))

  #expect(task(due: storedToday).isOverdue(now: now, timeZone: losAngeles.timeZone) == false)
  #expect(task(due: storedYesterday).isOverdue(now: now, timeZone: losAngeles.timeZone) == true)
}

/// Due soon is today or tomorrow for unresolved work, read in the user's day:
/// never an overdue task, a later day, or a finished one.
@Test
func dueSoonIsTodayOrTomorrow() throws {
  var losAngeles = Calendar(identifier: .gregorian)
  losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
  let now = try #require(losAngeles.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 21)))
  func stored(_ key: String) throws -> Date { try #require(LorvexDateFormatters.ymdUTC.date(from: key)) }

  #expect(task(due: try stored("2026-06-10")).isDueSoon(now: now, timeZone: losAngeles.timeZone))
  #expect(task(due: try stored("2026-06-11")).isDueSoon(now: now, timeZone: losAngeles.timeZone))
  #expect(!task(due: try stored("2026-06-12")).isDueSoon(now: now, timeZone: losAngeles.timeZone))
  #expect(!task(due: try stored("2026-06-09")).isDueSoon(now: now, timeZone: losAngeles.timeZone))
  #expect(!task(due: try stored("2026-06-10"), status: .completed).isDueSoon(now: now, timeZone: losAngeles.timeZone))
  #expect(!task(due: nil).isDueSoon(now: now, timeZone: losAngeles.timeZone))
}

/// The bridge between the storage frame (naive day at UTC midnight) and the
/// local calendar must hold in BOTH directions and on BOTH sides of UTC:
/// west of UTC an evening instant formatted via UTC names the next day, and
/// east of UTC a local midnight formatted via UTC names the previous day.
@Test
func plannedDayBridgeHoldsOnBothSidesOfUTC() throws {
  var losAngeles = Calendar(identifier: .gregorian)
  losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
  var shanghai = Calendar(identifier: .gregorian)
  shanghai.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))

  // West evening: local Jun 10, 20:00 (-7). Storage must name Jun 10.
  var west = DateComponents()
  west.year = 2026
  west.month = 6
  west.day = 10
  west.hour = 20
  let westEvening = try #require(losAngeles.date(from: west))
  let westStorage = PlannedDayBridge.storageDate(forLocalInstant: westEvening, timeZone: losAngeles.timeZone)
  #expect(LorvexDateFormatters.ymdUTC.string(from: westStorage) == "2026-06-10")

  // East midnight: local Jun 12, 00:00 (+8). Storage must name Jun 12.
  var east = DateComponents()
  east.year = 2026
  east.month = 6
  east.day = 12
  let eastMidnight = try #require(shanghai.date(from: east))
  let eastStorage = PlannedDayBridge.storageDate(forLocalInstant: eastMidnight, timeZone: shanghai.timeZone)
  #expect(LorvexDateFormatters.ymdUTC.string(from: eastStorage) == "2026-06-12")

  // Display direction: a stored Jun 6 day must surface as local Jun 6
  // midnight in both zones, and survive the round trip back to storage.
  let stored = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-06-06"))
  for calendar in [losAngeles, shanghai] {
    let display = PlannedDayBridge.displayDate(forStorageDate: stored, timeZone: calendar.timeZone)
    let day = calendar.dateComponents([.year, .month, .day], from: display)
    #expect(day.year == 2026 && day.month == 6 && day.day == 6)
    let roundTrip = PlannedDayBridge.storageDate(forLocalInstant: display, timeZone: calendar.timeZone)
    #expect(LorvexDateFormatters.ymdUTC.string(from: roundTrip) == "2026-06-06")
  }
}

@Test
func plannedDayBridgeShiftsTheProductDayWithoutUsingTheDeviceZone() throws {
  let tomorrow = try #require(
    PlannedDayBridge.storageDate(forLogicalDay: "2026-03-08", addingDays: 1))
  #expect(LorvexDateFormatters.ymdUTC.string(from: tomorrow) == "2026-03-09")
  #expect(PlannedDayBridge.storageDate(forLogicalDay: "not-a-day") == nil)
}

@Test
func logicalDayInstantRangeUsesProductTimezoneAndIncludesTheFinalDay() throws {
  let range = try #require(
    PlannedDayBridge.instantRange(
      fromLogicalDay: "2026-03-08",
      throughLogicalDay: "2026-03-08",
      timezoneName: "America/Los_Angeles"))
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

  let start = calendar.dateComponents([.year, .month, .day, .hour], from: range.start)
  let end = calendar.dateComponents([.year, .month, .day, .hour], from: range.endExclusive)
  #expect(start.year == 2026 && start.month == 3 && start.day == 8 && start.hour == 0)
  #expect(end.year == 2026 && end.month == 3 && end.day == 9 && end.hour == 0)
  // The US spring-forward day is 23 hours. Fixed 86400-second stepping would
  // not land on the next product midnight.
  #expect(range.endExclusive.timeIntervalSince(range.start) == 23 * 60 * 60)
}

/// A day picked in a control that shows the user's own calendar — Buddhist
/// in Thailand, Persian in Iran, or a Japanese era — stores as the same
/// Gregorian day key, and a stored key comes back as that same day in the
/// user's calendar. Copying year/month/day numbers between calendars instead
/// would store Buddhist 2569 as the year 2569 and show 2026 as Buddhist 2026.
@Test
func plannedDayBridgeHoldsInEveryCalendar() throws {
  let cases: [(Calendar.Identifier, String, Int, Int, Int)] = [
    (.buddhist, "Asia/Bangkok", 2569, 9, 29),
    (.japanese, "Asia/Tokyo", 8, 9, 29),
    (.persian, "Asia/Tehran", 1405, 7, 7),
    (.islamicUmmAlQura, "Asia/Riyadh", 0, 0, 0),
    (.hebrew, "Asia/Jerusalem", 0, 0, 0),
  ]
  let stored = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-09-29"))
  for (identifier, zoneID, year, month, day) in cases {
    let zone = try #require(TimeZone(identifier: zoneID))
    var calendar = Calendar(identifier: identifier)
    calendar.timeZone = zone

    let shown = PlannedDayBridge.displayDate(forStorageDate: stored, timeZone: zone)
    let parts = calendar.dateComponents([.year, .month, .day, .hour], from: shown)
    #expect(parts.hour == 0, "\(identifier) shows the day from its midnight")
    if year != 0 {
      #expect(
        parts.year == year && parts.month == month && parts.day == day,
        "\(identifier) names 2026-09-29 as \(year)-\(month)-\(day), not \(parts)")
    }

    // The control hands back midnight of the day it shows, in its calendar.
    let picked = try #require(calendar.date(from: calendar.dateComponents(
      [.era, .year, .month, .day], from: shown)))
    let roundTrip = PlannedDayBridge.storageDate(forLocalInstant: picked, timeZone: zone)
    #expect(LorvexDateFormatters.ymdUTC.string(from: roundTrip) == "2026-09-29", "\(identifier)")
    #expect(PlannedDayBridge.dayOffset(from: picked, toStorageDate: stored, timeZone: zone) == 0)
  }
}

/// Day offsets count whole local days, whatever the hour of `now` and on
/// either side of UTC.
@Test
func dayOffsetCountsLocalDays() throws {
  let stored = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-09-29"))
  let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
  let auckland = try #require(TimeZone(identifier: "Pacific/Auckland"))
  // 23:30 on Sep 28 in Los Angeles is already Sep 29 in UTC.
  let lateMonday = try #require(ISO8601DateFormatter().date(from: "2026-09-29T06:30:00Z"))
  #expect(PlannedDayBridge.dayOffset(from: lateMonday, toStorageDate: stored, timeZone: losAngeles) == 1)
  // 00:30 on Sep 30 in Auckland is still Sep 29 in UTC.
  let earlyWednesday = try #require(ISO8601DateFormatter().date(from: "2026-09-29T11:30:00Z"))
  #expect(PlannedDayBridge.dayOffset(from: earlyWednesday, toStorageDate: stored, timeZone: auckland) == -1)
}
