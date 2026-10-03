import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

private func calendar() -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
  calendar.firstWeekday = 1
  return calendar
}

private func date(_ string: String, _ calendar: Calendar) -> Date {
  let formatter = DateFormatter()
  formatter.calendar = calendar
  formatter.timeZone = calendar.timeZone
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter.date(from: string) ?? Date()
}

private func entry(_ date: String, value: Int = 1) -> HabitCompletionEntry {
  HabitCompletionEntry(
    habitID: "h1",
    completedDate: date,
    value: value,
    note: nil,
    createdAt: "\(date)T00:00:00Z",
    updatedAt: "\(date)T00:00:00Z"
  )
}

private func appleSourceFile(_ relativePath: String) throws -> String {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent(relativePath)
  return try String(contentsOf: url, encoding: .utf8)
}

@Test
func heatmapGridHasWeeksColumnsOfSevenDays() {
  let cal = calendar()
  let grid = HabitHeatmapModel.makeGrid(
    completions: [],
    targetCount: 1,
    weeks: 12,
    endDate: date("2026-05-28", cal),
    calendar: cal
  )
  #expect(grid.columns.count == 12)
  #expect(grid.columns.allSatisfy { $0.count == 7 })
}

@Test
func heatmapIntensityReflectsTargetThreshold() {
  let cal = calendar()
  // Target 2: a day with value 2 meets, value 1 is partial, value 0 is none.
  let grid = HabitHeatmapModel.makeGrid(
    completions: [
      entry("2026-05-25", value: 2),
      entry("2026-05-26", value: 1),
    ],
    targetCount: 2,
    weeks: 12,
    endDate: date("2026-05-28", cal),
    calendar: cal
  )
  let cells = grid.columns.flatMap { $0 }
  let met = cells.first { $0.date == "2026-05-25" }
  let partial = cells.first { $0.date == "2026-05-26" }
  let missed = cells.first { $0.date == "2026-05-27" }
  #expect(met?.intensity == .met)
  #expect(met?.value == 2)
  #expect(partial?.intensity == .partial)
  #expect(missed?.intensity == HabitHeatmapModel.Intensity.none)
}

@Test
func heatmapLevelBucketsByCompletionRatio() {
  // Empty and met endpoints.
  #expect(HabitHeatmapModel.level(value: 0, target: 5) == 0)
  #expect(HabitHeatmapModel.level(value: 5, target: 5) == 4)
  #expect(HabitHeatmapModel.level(value: 7, target: 5) == 4)  // over-target still met
  // Partial ratios bucket into 1…3 (target 8: 1/8, 3/8, 6/8).
  #expect(HabitHeatmapModel.level(value: 1, target: 8) == 1)
  #expect(HabitHeatmapModel.level(value: 3, target: 8) == 2)
  #expect(HabitHeatmapModel.level(value: 6, target: 8) == 3)
  // A binary habit only ever renders the empty/met endpoints.
  #expect(HabitHeatmapModel.level(value: 0, target: 1) == 0)
  #expect(HabitHeatmapModel.level(value: 1, target: 1) == 4)
}

@Test
func heatmapCellsCarryGradedLevels() {
  let cal = calendar()
  let grid = HabitHeatmapModel.makeGrid(
    completions: [
      entry("2026-05-24", value: 8),  // met → 4
      entry("2026-05-25", value: 6),  // 0.75 → 3
      entry("2026-05-26", value: 3),  // 0.375 → 2
      entry("2026-05-27", value: 1),  // 0.125 → 1
    ],
    targetCount: 8,
    weeks: 12,
    endDate: date("2026-05-28", cal),
    calendar: cal
  )
  let cells = grid.columns.flatMap { $0 }
  #expect(cells.first { $0.date == "2026-05-24" }?.level == 4)
  #expect(cells.first { $0.date == "2026-05-25" }?.level == 3)
  #expect(cells.first { $0.date == "2026-05-26" }?.level == 2)
  #expect(cells.first { $0.date == "2026-05-27" }?.level == 1)
  // Tracked-but-empty end day sits at level 0.
  #expect(cells.first { $0.date == "2026-05-28" }?.level == 0)
}

@Test
func heatmapSumsMultipleEntriesPerDay() {
  let cal = calendar()
  let grid = HabitHeatmapModel.makeGrid(
    completions: [
      entry("2026-05-27", value: 1),
      entry("2026-05-27", value: 1),
      entry("2026-05-27", value: 1),
    ],
    targetCount: 3,
    weeks: 4,
    endDate: date("2026-05-28", cal),
    calendar: cal
  )
  let cell = grid.columns.flatMap { $0 }.first { $0.date == "2026-05-27" }
  #expect(cell?.value == 3)
  #expect(cell?.intensity == .met)
}

@Test
func heatmapMarksFutureDaysAbsent() {
  let cal = calendar()
  // 2026-05-28 is a Thursday; with firstWeekday=1 (Sunday), the last column's
  // Fri/Sat are future relative to the end date and must be absent slots.
  let grid = HabitHeatmapModel.makeGrid(
    completions: [],
    targetCount: 1,
    weeks: 12,
    endDate: date("2026-05-28", cal),
    calendar: cal
  )
  let lastColumn = grid.columns.last
  #expect(lastColumn != nil)
  // Days strictly after the end date have empty date strings and .absent.
  let absentCells = lastColumn?.filter { $0.intensity == .absent } ?? []
  #expect(absentCells.allSatisfy { $0.date.isEmpty })
  // The end date itself is present and tracked (none, since no completions).
  let endCell = grid.columns.flatMap { $0 }.first { $0.date == "2026-05-28" }
  #expect(endCell?.intensity == HabitHeatmapModel.Intensity.none)
}

@Test
func heatmapZeroWeeksIsEmpty() {
  let cal = calendar()
  let grid = HabitHeatmapModel.makeGrid(
    completions: [entry("2026-05-28")],
    targetCount: 1,
    weeks: 0,
    endDate: date("2026-05-28", cal),
    calendar: cal
  )
  #expect(grid == .empty)
}

/// Eight ISO weeks (Monday first) ending Saturday 2026-10-03: Aug 10 to Oct 4.
private func isoWeeksEndingOctober3(locale: Locale) -> HabitHeatmapModel.Grid {
  var iso = Calendar(identifier: .gregorian)
  iso.timeZone = TimeZone(identifier: "UTC") ?? .current
  iso.firstWeekday = 2
  iso.minimumDaysInFirstWeek = 4
  return HabitHeatmapModel.makeGrid(
    completions: [], targetCount: 1, weeks: 8, endDate: date("2026-10-03", iso), calendar: iso,
    locale: locale)
}

@Test
func heatmapMonthLabelsMarkWhereAMonthOfTheLocaleCalendarBegins() {
  // Gregorian: September begins in the week of Aug 31, October in the newest week.
  let gregorian = isoWeeksEndingOctober3(locale: Locale(identifier: "en_US"))
  #expect(gregorian.monthLabels == [nil, nil, nil, "Sep", nil, nil, nil, "Oct"])
  // Umm al-Qura: Rabi' al-Awwal 1448 begins on Aug 14 and Rabi' al-Akhir on
  // Sep 12, so those weeks carry the Hijri names and October 1 carries none.
  let hijri = isoWeeksEndingOctober3(locale: Locale(identifier: "ar_SA"))
  #expect(hijri.monthLabels == ["ربيع الأول", nil, nil, nil, "ربيع الآخر", nil, nil, nil])
}

@Test
func monthLabelsKeepTheirColumnsWhileTheyFit() {
  let positions = HabitHeatmapModel.monthLabelPositions(
    starts: [0, 13, 26, 39, 52, 65, 78, 91], widths: [40, 0, 0, 0, 58, 0, 0, 0],
    leadingEdge: 0, trailingEdge: 200, gap: 4)
  #expect(positions == [0, nil, nil, nil, 52, nil, nil, nil])
}

@Test
func anOlderMonthLabelThatWouldRunIntoTheNextIsLeftOut() {
  // Two long names four weeks apart: the newer month keeps its name.
  let positions = HabitHeatmapModel.monthLabelPositions(
    starts: [0, 13, 26, 39, 52, 65, 78, 91], widths: [57, 0, 0, 0, 58, 0, 0, 0],
    leadingEdge: 0, trailingEdge: 200, gap: 4)
  #expect(positions == [nil, nil, nil, nil, 52, nil, nil, nil])
}

@Test
func aMonthLabelNearTheNewestWeekEndsAtTheGridsEdge() {
  // October began in the newest week: its name shifts back to end at the
  // edge, and September's still clears it.
  let shifted = HabitHeatmapModel.monthLabelPositions(
    starts: [0, 13, 26, 39, 52, 65], widths: [20, 0, 0, 0, 0, 30],
    leadingEdge: 0, trailingEdge: 75, gap: 4)
  #expect(shifted == [0, nil, nil, nil, nil, 45])
  // A name wider than the whole grid has nowhere to go.
  let tooWide = HabitHeatmapModel.monthLabelPositions(
    starts: [0], widths: [50], leadingEdge: 0, trailingEdge: 30, gap: 4)
  #expect(tooWide == [nil])
}

@Test
func monthLabelsOfHiddenWeeksAreLeftOut() {
  let positions = HabitHeatmapModel.monthLabelPositions(
    starts: [nil, nil, 0, 13], widths: [20, 0, 0, 20],
    leadingEdge: 0, trailingEdge: 23, gap: 4)
  #expect(positions == [nil, nil, nil, 3])
}

@Test
func weekdayInitialsRotateWithFirstWeekday() {
  var sundayFirst = calendar()
  sundayFirst.firstWeekday = 1
  var mondayFirst = calendar()
  mondayFirst.firstWeekday = 2

  let sunday = HabitHeatmapModel.weekdayInitials(calendar: sundayFirst)
  let monday = HabitHeatmapModel.weekdayInitials(calendar: mondayFirst)
  #expect(sunday.count == 7)
  #expect(monday.count == 7)
  // Monday-first is the Sunday-first list rotated by one.
  #expect(monday == Array(sunday[1...] + sunday[..<1]))
}

@Test
func weekdayInitialsFollowTheLocaleLanguage() {
  var sundayFirst = calendar()
  sundayFirst.firstWeekday = 1
  let chinese = HabitHeatmapModel.weekdayInitials(
    calendar: sundayFirst, locale: Locale(identifier: "zh_Hans_CN"))
  let english = HabitHeatmapModel.weekdayInitials(
    calendar: sundayFirst, locale: Locale(identifier: "en_US"))
  #expect(chinese == ["日", "一", "二", "三", "四", "五", "六"])
  #expect(english == ["S", "M", "T", "W", "T", "F", "S"])
}

@Test
func historyPanelCachesGridOutsideBody() throws {
  let source = try appleSourceFile("Sources/LorvexApple/Views/HabitHistoryPanel.swift")

  #expect(source.contains("@State private var cache: HistoryCache"))
  #expect(source.contains(".onChange(of: detail)"))
  #expect(source.contains("private static func makeCache("))
  #expect(source.contains("cache.grid.columns"))
  // The grid is built in one place, the cache builder, never per body pass.
  #expect(source.components(separatedBy: "HabitHeatmapModel.makeGrid(").count == 2)
}
