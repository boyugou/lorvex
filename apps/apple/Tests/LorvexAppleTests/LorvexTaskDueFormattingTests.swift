import Foundation
import LorvexCore
import Testing

private func task(due: Date?) -> LorvexTask {
  LorvexTask(
    id: "t", title: "T", notes: "", priority: .p2, status: .open,
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

  #expect(task(due: earlierToday).isOverdue(now: now, calendar: cal) == false)
  #expect(task(due: yesterday).isOverdue(now: now, calendar: cal) == true)
  #expect(task(due: tomorrow).isOverdue(now: now, calendar: cal) == false)
  #expect(task(due: nil).isOverdue(now: now, calendar: cal) == false)
}

/// The relative label is present exactly when the task has a due date.
@Test
func dueRelativeLabelPresenceFollowsDueDate() {
  let now = Date(timeIntervalSince1970: 1_780_000_000)
  #expect(task(due: nil).cachedDueRelativeLabel(now: now, calendar: cal) == nil)
  #expect(task(due: now).cachedDueRelativeLabel(now: now, calendar: cal) != nil)
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

  #expect(task(due: storedToday).isOverdue(now: now, calendar: losAngeles) == false)
  #expect(task(due: storedYesterday).isOverdue(now: now, calendar: losAngeles) == true)
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
  let westStorage = PlannedDayBridge.storageDate(forLocalInstant: westEvening, calendar: losAngeles)
  #expect(LorvexDateFormatters.ymdUTC.string(from: westStorage) == "2026-06-10")

  // East midnight: local Jun 12, 00:00 (+8). Storage must name Jun 12.
  var east = DateComponents()
  east.year = 2026
  east.month = 6
  east.day = 12
  let eastMidnight = try #require(shanghai.date(from: east))
  let eastStorage = PlannedDayBridge.storageDate(forLocalInstant: eastMidnight, calendar: shanghai)
  #expect(LorvexDateFormatters.ymdUTC.string(from: eastStorage) == "2026-06-12")

  // Display direction: a stored Jun 6 day must surface as local Jun 6
  // midnight in both zones, and survive the round trip back to storage.
  let stored = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-06-06"))
  for calendar in [losAngeles, shanghai] {
    let display = PlannedDayBridge.displayDate(forStorageDate: stored, calendar: calendar)
    let day = calendar.dateComponents([.year, .month, .day], from: display)
    #expect(day.year == 2026 && day.month == 6 && day.day == 6)
    let roundTrip = PlannedDayBridge.storageDate(forLocalInstant: display, calendar: calendar)
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
