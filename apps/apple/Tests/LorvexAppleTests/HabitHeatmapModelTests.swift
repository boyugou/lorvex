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
func heatmapViewCachesGridOutsideBody() throws {
  let source = try appleSourceFile("Sources/LorvexApple/Views/HabitHeatmapView.swift")

  #expect(source.contains("@State private var cachedGrid: HabitHeatmapModel.Grid"))
  #expect(source.contains("heatmap(grid: cachedGrid)"))
  #expect(source.contains(".onChange(of: detail)"))
  #expect(source.contains("private static func makeGrid("))
  #expect(!source.contains("heatmap(grid: grid(for: detail))"))
}
