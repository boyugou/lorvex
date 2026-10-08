import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// The VoiceOver structure of Mac surfaces whose elements are built from
/// several views: a row whose icon reads as a raw symbol name, a menu whose
/// label is exposed child by child, a block whose label reads once per text
/// line. A unit test cannot host the accessibility tree, so the modifiers that
/// give each surface its structure are pinned in the source, and the spoken
/// text is pinned as a value. The tour's `-uiPreviewDumpAX` run reads the
/// real tree.
@Suite("Mac VoiceOver structure")
@MainActor
struct MacAccessibilityStructureTests {
  private static func source(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(contentsOf: root.appending(path: "Sources/LorvexApple/\(relativePath)"), encoding: .utf8)
  }

  /// Whether `second` appears in `source` after `first`, within `limit`
  /// characters of it: how a modifier is pinned to the view it follows.
  private static func follows(
    _ second: String, _ first: String, in source: String, within limit: Int = 600
  ) -> Bool {
    guard let start = source.range(of: first) else { return false }
    let tail = source[start.upperBound...].prefix(limit)
    return tail.contains(second)
  }

  private static func occurrences(of needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
  }

  // MARK: Values

  @Test("a list is spoken with its name and its counts, or as empty")
  func listSpokenSummary() {
    func list(open: Int, total: Int) -> LorvexList {
      LorvexList(
        id: "work", name: "Work", color: nil, icon: nil, description: nil, openCount: open,
        totalCount: total, updatedAt: "2026-10-01T00:00:00Z")
    }
    let populated = list(open: 4, total: 10).spokenSummary
    #expect(populated.contains("Work"))
    #expect(populated.contains("4"))
    #expect(populated.contains("10"))
    let empty = list(open: 0, total: 0).spokenSummary
    #expect(empty.contains("Work"))
    #expect(!empty.contains("0"))
    #expect(empty != populated)
  }

  @Test("blocks read day by day, in time order within a day")
  func earlierBlocksReadFirst() {
    // (day index, start minute) in the order they must read.
    let blocks = [(0, 0), (0, 9 * 60), (0, 9 * 60 + 45), (0, 24 * 60 - 1), (1, 0), (1, 14 * 60), (6, 8 * 60)]
    let priorities = blocks.map {
      CalendarWeekGridView.accessibilitySortPriority(dayIndex: $0.0, totalDays: 7, startMinutes: $0.1)
    }
    #expect(priorities == priorities.sorted(by: >))
    #expect(Set(priorities).count == blocks.count)
    #expect(priorities.allSatisfy { $0 > 0 })
  }

  // MARK: Sidebar and Settings

  @Test("a list icon is decoration everywhere it is drawn")
  func listIconIsHidden() throws {
    let icon = try Self.source("Views/LorvexListIconView.swift")
    #expect(Self.follows(".accessibilityHidden(true)", ".background(backgroundView)", in: icon, within: 80))
  }

  @Test("sidebar rows hide their icon, and a list row is one element that reads its counts")
  func sidebarRows() throws {
    let components = try Self.source("Views/SidebarComponents.swift")
    // The list row and the footer row each hide their icon column.
    #expect(Self.occurrences(of: ".accessibilityHidden(true)", in: components) == 2)
    #expect(components.contains("accessibilityElement(children: .ignore).accessibilityLabel(label)"))
    let lists = try Self.source("Views/SidebarListSection.swift")
    #expect(lists.contains("spokenLabel: list.spokenSummary"))
    let catalog = try Self.source("Views/ListCatalogRow.swift")
    #expect(catalog.contains(".accessibilityLabel(list.spokenSummary)"))
  }

  @Test("the Settings sidebar hides its symbols and marks its group titles as headings")
  func settingsSidebar() throws {
    let chrome = try Self.source("Views/SettingsChrome.swift")
    #expect(Self.follows(".accessibilityHidden(true)", "Image(systemName: category.systemImage)", in: chrome, within: 160))
    #expect(Self.follows(".accessibilityAddTraits(.isHeader)", "Text(group.title)", in: chrome, within: 200))
  }

  // MARK: Detail pages

  @Test("a header chip's symbol is hidden beside a title, so a menu does not expose it as a stop")
  func headerChipSymbol() throws {
    let actions = try Self.source("Views/TaskDetailActionsSection.swift")
    #expect(Self.follows(".accessibilityHidden(title != nil)", "Image(systemName: systemImage)", in: actions, within: 400))
  }

  @Test("an inspector property hides its row icon, and an addition its plus")
  func inspectorPropertySymbols() throws {
    let properties = try Self.source("Views/InspectorProperties.swift")
    #expect(Self.follows(".accessibilityHidden(true)", "Image(systemName: \"plus\")", in: properties, within: 120))
    #expect(Self.follows(".accessibilityHidden(true)", "Image(systemName: row.systemImage)", in: properties, within: 300))
  }

  @Test("inspector and detail section titles are headings")
  func sectionTitlesAreHeadings() throws {
    for file in [
      "HabitHistoryPanel.swift", "HabitProgressPanel.swift", "HabitWeekdayPanel.swift",
      "TaskDetailChecklistSection.swift", "TaskDetailNotesSection.swift",
    ] {
      let panel = try Self.source("Views/\(file)")
      #expect(panel.contains(".accessibilityAddTraits(.isHeader)"), "\(file)")
    }
  }

  @Test("the checklist's bar is hidden: the count beside its title says the same in words")
  func checklistBarIsHidden() throws {
    let checklist = try Self.source("Views/TaskDetailChecklistSection.swift")
    #expect(
      Self.follows(
        ".accessibilityHidden(true)", "LorvexProgressBar(value: completionFraction)", in: checklist,
        within: 100))
  }

  @Test("the habit heatmap's summary rides an overlay, so its frame is the card's")
  func heatmapSummaryIsOnAnOverlay() throws {
    let history = try Self.source("Views/HabitHistoryPanel.swift")
    #expect(Self.follows(".accessibilityHidden(true)", ".tint(identity)", in: history, within: 500))
    #expect(Self.follows(".accessibilityLabel(accessibilitySummary)", ".overlay {", in: history, within: 160))
    #expect(
      !history.contains(
        ".accessibilityElement(children: .ignore)\n    .accessibilityLabel(accessibilitySummary)"))
  }

  @Test("a memory row carries its tooltip once, after it is combined")
  func memoryRowHelpIsOnTheCombinedElement() throws {
    let row = try Self.source("Views/MemoryEntryRow.swift")
    let combine = try #require(row.range(of: ".accessibilityElement(children: .combine)"))
    let help = try #require(row.range(of: ".help("))
    #expect(combine.lowerBound < help.lowerBound)
    #expect(row.contains(".accessibilityAddTraits(.isButton)"))
    #expect(row.contains(".accessibilityAction { edit() }"))
  }

  // MARK: Editors and controls

  @Test("a plain text editor's placeholder is the text view's placeholder, not a second element")
  func editorPlaceholder() throws {
    let editor = try Self.source("Views/LorvexPlainTextEditor.swift")
    #expect(Self.follows(".accessibilityHidden(true)", "Text(placeholder)", in: editor, within: 700))
    #expect(editor.contains("textView.setAccessibilityPlaceholderValue(placeholder)"))
  }

  @Test("decorative glyphs beside a field or a title are not read")
  func decorativeGlyphsAreHidden() throws {
    let pins = [
      ("Views/MenuBarStatusView.swift", "Image(systemName: \"plus.circle.fill\")"),
      ("Views/LorvexDateChip.swift", "Image(systemName: includesTime ? \"bell\" : \"calendar\")"),
      ("Onboarding/SetupWizardPermissionsStep.swift", "Image(systemName: icon)"),
      ("Views/CalendarEventInspector.swift", "Image(systemName: icon)"),
    ]
    for (path, image) in pins {
      let source = try Self.source(path)
      #expect(Self.follows(".accessibilityHidden(true)", image, in: source, within: 260), "\(path)")
    }
  }

  @Test("Suggest Times offers Clear Times as an action, since its menu segment has no name")
  func suggestTimesOffersClearTimes() throws {
    let controls = try Self.source("Views/TodayControls.swift")
    #expect(controls.contains(".accessibilityActions {"))
    #expect(controls.contains("Button(TodayCalmCopy.clearTimes, action: clear)"))
  }

  // MARK: Week grid

  @Test("an event block is one element and has a press action")
  func eventBlockIsOneElement() throws {
    let block = try Self.source("Views/CalendarWeekGridEventBlock.swift")
    #expect(Self.follows(".accessibilityLabel(label)", ".accessibilityElement(children: .ignore)", in: block, within: 200))
    #expect(block.contains(".accessibilityAction { selectEvent(block.event) }"))
    #expect(block.contains("dayIndex: dayIndex, totalDays: totalDays, startMinutes: block.startMin"))
    #expect(block.contains("calendarEventAccessibilityLabel(block.event), on: day, totalDays: totalDays"))
  }

  @Test("a timed task block is one element: it opens by default and completes as a named action")
  func taskBlockIsOneElement() throws {
    let block = try Self.source("Views/CalendarWeekGridTaskBlock.swift")
    #expect(Self.follows(".accessibilityLabel(label)", ".accessibilityElement(children: .ignore)", in: block, within: 200))
    #expect(block.contains(".accessibilityAction { openTask(block.task) }"))
    #expect(block.contains(".accessibilityAction(named: taskCompletionLabel(isDone: block.isDone))"))
    #expect(block.contains("dayIndex: dayIndex, totalDays: totalDays, startMinutes: block.startMin"))
    #expect(block.contains("on: day, totalDays: totalDays)"))
  }

  @Test("the all-day pills are single elements, the hour labels are not stops, day headers are headings")
  func weekGridChrome() throws {
    let chrome = try Self.source("Views/CalendarWeekGridChrome.swift")
    #expect(Self.occurrences(of: ".accessibilityElement(children: .ignore)", in: chrome) == 2)
    #expect(chrome.contains(".accessibilityAction { selectEvent(event) }"))
    #expect(chrome.contains(".accessibilityAction { openTask(task) }"))
    #expect(chrome.contains(".accessibilityAction(named: taskCompletionLabel(isDone: isDone))"))
    #expect(Self.follows(".accessibilityHidden(true)", ".frame(width: gutter)", in: chrome, within: 240))
    #expect(
      Self.follows(
        ".accessibilityAddTraits(.isHeader)", "CalendarWeekDayLoadCaption.nothingPlanned)\")", in: chrome,
        within: 80))
  }

  @Test("the all-day strip's day columns are containers named by their day; the grid's are not")
  func dayColumnsAreGrouped() throws {
    let chrome = try Self.source("Views/CalendarWeekGridChrome.swift")
    #expect(chrome.contains("if totalDays > 1 {"))
    #expect(Self.follows(".accessibilityLabel(headerAccessibilityLabel(day.date))", ".accessibilityElement(children: .contain)", in: chrome, within: 120))
    #expect(chrome.contains(".accessibilityHidden(isEmpty)"))
    #expect(chrome.contains("allDayColumn(day), day: day, totalDays: columns.count,"))
    // The time grid's blocks are ordered by priority across the whole grid, which a
    // container per day would not honor, so its columns stay plain.
    let grid = try Self.source("Views/CalendarWeekGridView.swift")
    #expect(!grid.contains("groupedByDay("))
  }
}
