import Foundation
import LorvexCore
import Testing

/// The import summary names records the way people know them and says what
/// happened to each, in LorvexCore's words, the same on the Mac and iPhone.
@Suite("Import summary lines")
struct ImportSummaryLineTests {
  private func texts(_ summary: LorvexImportSummary, visible: Int = 5) -> [String] {
    ImportSummaryLine.lines(for: summary, maxVisibleIssueLines: visible).map(\.text)
  }

  private func task(_ id: String, _ title: String) -> LorvexImportIssue.Record {
    .named(id: id, name: title)
  }

  private var reviewDay: String {
    let date = LorvexDateFormatters.ymdUTC.date(from: "2026-09-28") ?? Date()
    return LorvexDateFormatters.string(date, dateStyle: .medium, timeZone: .gmt)
  }

  private var mixed: LorvexImportSummary {
    LorvexImportSummary(
      results: [
        LorvexImportCategoryResult(category: .tags, imported: 3, skipped: 2),
        LorvexImportCategoryResult(category: .tasks, imported: 1, skipped: 0),
      ],
      issues: [
        LorvexImportIssue(
          category: .tasks, record: task("t-1", "Buy milk"), outcome: .notImported, detail: "x"),
        LorvexImportIssue(
          category: .tasks, record: task("t-2", "Call mom"),
          outcome: .restoredWithout(.recurrence), detail: "x"),
        LorvexImportIssue(
          category: .dailyReviews, record: .day("2026-09-28"), outcome: .notImported, detail: "x"),
        LorvexImportIssue(
          category: .tasks, record: task("t-2", "Call mom"),
          outcome: .restoredWithout(.reminders), detail: "x"),
        LorvexImportIssue(
          category: .calendarEvents, record: .wholeCategory, outcome: .notImported, detail: "x"),
      ])
  }

  @Test("Records are named, grouped by outcome, and a task's missing details share one line")
  func groupedLines() {
    #expect(
      texts(mixed) == [
        "4 imported records, 2 already present",
        "Tags: 3 imported, 2 skipped",
        "Tasks: 1 imported",
        "Not imported:",
        "Tasks: “Buy milk”",
        "Daily Reviews: \(reviewDay)",
        "Calendar Events",
        "Restored without these details:",
        "“Call mom”: reminders and repeat rule",
      ])
    let lines = ImportSummaryLine.lines(for: mixed, maxVisibleIssueLines: 5)
    #expect(lines.first?.style == .headline(systemImage: "checkmark.circle"))
    #expect(lines.first?.tone == .success)
    #expect(lines[1].tone == .secondary)
    #expect(lines.filter { $0.style == .heading }.map(\.text) == [
      "Not imported:", "Restored without these details:",
    ])
    #expect(lines.filter { $0.style == .heading }.allSatisfy { $0.tone == .warning })
    #expect(lines.filter { $0.style == .item }.count == 4)
    #expect(lines.filter { $0.style == .item }.allSatisfy { $0.tone == .primary })
  }

  @Test("Issue lines stop at the cap, and a last line counts the rest")
  func cappedLines() {
    #expect(
      texts(mixed, visible: 2) == [
        "4 imported records, 2 already present",
        "Tags: 3 imported, 2 skipped",
        "Tasks: 1 imported",
        "Not imported:",
        "Tasks: “Buy milk”",
        "Daily Reviews: \(reviewDay)",
        "and 2 more…",
      ])
    let lines = ImportSummaryLine.lines(for: mixed, maxVisibleIssueLines: 2)
    #expect(lines.last?.tone == .secondary)
  }

  @Test("A failed import warns in its headline, and a repeated line shows once")
  func nothingImported() {
    let summary = LorvexImportSummary(
      results: [LorvexImportCategoryResult(category: .taskCalendarEventLinks, imported: 0, skipped: 0)],
      issues: [
        LorvexImportIssue(
          category: .taskCalendarEventLinks, record: .named(id: "t-1:e-1", name: nil),
          outcome: .notImported, detail: "x"),
        LorvexImportIssue(
          category: .taskCalendarEventLinks, record: .named(id: "t-2:e-2", name: nil),
          outcome: .notImported, detail: "x"),
      ])
    let lines = ImportSummaryLine.lines(for: summary, maxVisibleIssueLines: 5)

    #expect(
      lines.map(\.text) == [
        "0 imported records",
        "Task–Event Links: 0 imported",
        "Not imported:",
        "Task–Event Links",
      ])
    #expect(lines.first?.style == .headline(systemImage: "exclamationmark.triangle"))
    #expect(lines.first?.tone == .warning)
  }

  @Test("A refused backup shows only the reason")
  func refusedBackup() {
    let lines = ImportSummaryLine.lines(
      for: LorvexImportSummary(rejection: .emptyFile), maxVisibleIssueLines: 5)

    #expect(lines.map(\.text) == ["The selected file is empty."])
    #expect(lines.first?.style == .headline(systemImage: "exclamationmark.triangle"))
    #expect(lines.first?.tone == .warning)
  }

  @Test("Every detail a task can lack has its own name")
  func partNames() {
    #expect(
      LorvexImportIssue.Part.allCases.map(\.localizedName) == [
        "planned time", "list", "checklist", "reminders", "repeat rule", "dependencies", "status",
        "history",
      ])
  }
}
