import Foundation
import Testing

@Test
func calendarWeekGridReanchorsOnWeekNavigationNotOnEdits() throws {
  let source = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexApple/Views/CalendarWeekGridView.swift"),
    encoding: .utf8
  )
  let components = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexApple/Views/CalendarWeekGridComponents.swift"),
    encoding: .utf8
  )

  #expect(source.contains("let scrollSignature = calendarWeekScrollAnchorSignature"))
  #expect(source.contains(".onChange(of: scrollSignature)"))
  #expect(source.contains("lorvexAnimated(.snappy(duration: 0.18))"))
  // Block geometry (startMin/endMin) must NOT be in the scroll signature: moving
  // or resizing an event must not yank the scroll position back to the anchor.
  // Re-scroll fires only on week navigation (weekStart change).
  #expect(!components.contains("timedIDs = columns.flatMap { day in"))
}

@Test
func calendarWeekGridScheduledTaskPillsOpenTaskDetail() throws {
  let root = packageRoot()
  let grid = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWeekGridView.swift"),
    encoding: .utf8
  )
  let chrome = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWeekGridChrome.swift"),
    encoding: .utf8
  )
  let workspace = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWorkspaceView.swift"),
    encoding: .utf8
  )

  #expect(grid.contains("let openTask: (LorvexTask) -> Void"))
  #expect(chrome.contains(".onTapGesture { openTask(task) }"))
  #expect(workspace.contains("openTask: { task in"))
  #expect(workspace.contains("store.selectTaskFromList(task.id)"))
}

@Test
func calendarWeekGridDaySeparatorsDoNotConsumeColumnWidth() throws {
  let source = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexApple/Views/CalendarWeekGridView.swift"),
    encoding: .utf8
  )

  #expect(source.contains("Draw the column separator as a trailing overlay"))
  #expect(source.contains(".overlay(alignment: .trailing)"))
  #expect(source.contains(".frame(width: 1)"))
  #expect(!source.contains("ForEach(Array(columns.enumerated()), id: \\.element.id) { index, day in\n              dayColumn(day, dayIndex: index, totalDays: columns.count)\n              Divider()"))
}

@Test
func calendarWeekGridCursorsUseCursorRectsInsteadOfPushPop() throws {
  // The grid's pointer cursors go through one shared cursor-rect view. Cursor
  // rects compose (the topmost rect under the pointer wins) so an event block's
  // pointing-hand and its resize handles coexist — unlike NSCursor.push()/pop(),
  // which fight each other and can leak when a block scrolls away mid-hover.
  let source = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexApple/Views/CalendarWeekGridComponents.swift"),
    encoding: .utf8
  )

  #expect(source.contains("NSViewRepresentable"))
  #expect(source.contains("resetCursorRects()"))
  #expect(source.contains("addCursorRect(bounds, cursor: cursor)"))
  #expect(source.contains("CalendarCursorView(cursor: .resizeUpDown)"))
  #expect(source.contains("CalendarCursorView(cursor: .pointingHand)"))
  #expect(!source.contains("NSCursor.resizeUpDown.push()"))
  #expect(!source.contains("NSCursor.pop()"))
}

@Test
func calendarWeekGridInteractiveEventsShowPointingHandCursor() throws {
  let eventBlock = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexApple/Views/CalendarWeekGridEventBlock.swift"),
    encoding: .utf8
  )
  let chrome = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexApple/Views/CalendarWeekGridChrome.swift"),
    encoding: .utf8
  )

  // Timed blocks and all-day pills (event + task) take the pointing-hand cursor.
  #expect(eventBlock.contains(".calendarPointingHandCursor()"))
  #expect(chrome.contains(".calendarPointingHandCursor()"))
  // The all-day strip's pills / highlights route their radius through the design
  // token rather than a bare `4` literal.
  #expect(chrome.contains("RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)"))
  #expect(!chrome.contains("RoundedRectangle(cornerRadius: 4)"))
}

@Test
func calendarWeekGridEventBlocksUseCompactMetrics() throws {
  let source = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexApple/Views/CalendarWeekGridEventBlock.swift"),
    encoding: .utf8
  )

  #expect(source.contains("private enum CalendarEventBlockMetrics"))
  #expect(source.contains("static let minimumHeight: CGFloat = 16"))
  #expect(source.contains("static let compactHeightThreshold: CGFloat = 28"))
  #expect(source.contains("static let timeHeightThreshold: CGFloat = 34"))
  #expect(source.contains("static let accentRailWidth: CGFloat = 2.5"))
  #expect(source.contains("static let activeShadowRadius: CGFloat = 7"))
  #expect(source.contains("CalendarEventBlockContent("))
  #expect(source.contains("private struct CalendarEventBlockContent: View"))
  #expect(source.contains(".lineLimit(titleLineLimit)"))
  #expect(source.contains("renderedHeight >= CalendarEventBlockMetrics.timeHeightThreshold"))
  #expect(source.contains("renderedHeight < CalendarEventBlockMetrics.compactHeightThreshold ? 1 : 2"))
  // Fill and stroke strengthen for the active (hover/drag) block and for the
  // selected block whose inspector is open.
  #expect(source.contains("color.opacity(active != nil || isSelected ? 0.24 : 0.16)"))
  #expect(source.contains("lineWidth: isSelected ? 1.5 : (active == nil ? 0.5 : 1)"))
  #expect(source.contains("CalendarEventBlockMetrics.resizeHandleHitHeight"))
  #expect(source.contains("CalendarEventBlockMetrics.resizeHandleWidth"))
  #expect(!source.contains("let baseHeight = max(CGFloat(block.endMin - block.startMin) / 60 * hourHeight, 16)"))
  #expect(!source.contains(".padding(.horizontal, 4)"))
  #expect(!source.contains(".background(color.opacity(0.22)"))
}

@Test
func calendarNavigationButtonsExposeCommandArrowShortcuts() throws {
  let source = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexApple/Views/CalendarWorkspaceNavigationBar.swift"),
    encoding: .utf8
  )

  #expect(source.contains(".keyboardShortcut(.leftArrow, modifiers: [.command])"))
  #expect(source.contains(".keyboardShortcut(.rightArrow, modifiers: [.command])"))
}

@Test
func calendarWorkspaceOffersDayWeekAndMonthModes() throws {
  let root = packageRoot()
  let workspace = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWorkspaceView.swift"),
    encoding: .utf8
  )
  let model = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWorkspaceModels.swift"),
    encoding: .utf8
  )
  let grid = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWeekGridView.swift"),
    encoding: .utf8
  )
  let nav = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWorkspaceNavigationBar.swift"),
    encoding: .utf8
  )

  #expect(model.contains("case day"))
  #expect(model.contains("case week"))
  #expect(model.contains("case month"))
  // The Agenda (.list) mode was removed and never reintroduced.
  #expect(!model.contains("case list"))
  #expect(grid.contains("var visibleDayCount: Int = 7"))
  #expect(grid.contains("dayCount: visibleDayCount"))
  #expect(workspace.contains("visibleDayCount: 1"))
  #expect(workspace.contains("fetchVisibleDay(anchorDate)"))
  #expect(nav.contains(#""calendar.mode.day""#))
  #expect(nav.contains(#""calendar.mode.week""#))
  #expect(nav.contains(#""calendar.mode.month""#))
  #expect(!nav.contains(#""calendar.mode.list""#))
}

@Test
func calendarWeekGridOverflowBadgeOpensHiddenEventPopover() throws {
  let source = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexApple/Views/CalendarWeekGridView.swift"),
    encoding: .utf8
  )

  #expect(source.contains("@State private var overflowPopoverDayID"))
  #expect(source.contains("Button {"))
  #expect(source.contains("overflowPopoverDayID = day.id"))
  #expect(source.contains(".popover("))
  #expect(source.contains("overflowPopover(blocks: hidden)"))
  #expect(source.contains("ForEach(blocks.sorted { $0.startMin < $1.startMin })"))
  // A hidden-event row now opens the detail inspector (the 3-panel selection)
  // rather than jumping straight to the edit sheet.
  #expect(source.contains("selectEvent(block.event)"))
  #expect(!source.contains(".allowsHitTesting(false)\n        .accessibilityLabel(\"\\(hidden.count) more events\")"))
}

@Test
func calendarWeekGridShowsNowGuideAcrossEveryDayColumn() throws {
  let root = packageRoot()
  let grid = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWeekGridView.swift"),
    encoding: .utf8
  )
  let chrome = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWeekGridChrome.swift"),
    encoding: .utf8
  )

  #expect(grid.contains("nowLine(now: context.date, isToday: isToday(day.date))"))
  #expect(!grid.contains("if isToday(day.date) {\n          TimelineView(.periodic"))
  #expect(chrome.contains("func nowLine(now: Date, isToday: Bool)"))
  #expect(chrome.contains("Color.secondary.opacity(0.22)"))
  #expect(chrome.contains("Rectangle().fill(lineColor).frame(height: isToday ? 1.5 : 1)"))
}

@Test
func calendarWeekGridShowsCalmEmptyWeekOverlay() throws {
  let source = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexApple/Views/CalendarWeekGridView.swift"),
    encoding: .utf8
  )
  let components = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexApple/Views/CalendarWeekGridComponents.swift"),
    encoding: .utf8
  )

  #expect(source.contains("private func isEmptyWeek(_ columns: [CalendarGridDay]) -> Bool"))
  #expect(source.contains("$0.allDayEvents.isEmpty && $0.scheduledTasks.isEmpty && $0.timedBlocks.isEmpty"))
  #expect(source.contains("private func emptyWeekCreateTarget(_ columns: [CalendarGridDay])"))
  #expect(source.contains("CalendarWeekEmptyOverlay"))
  #expect(source.contains("CalendarWeekEmptyOverlay(visibleDayCount: visibleDayCount)"))
  #expect(components.contains("private var isSingleDay: Bool"))
  #expect(components.contains(#".accessibilityIdentifier(isSingleDay ? "calendar.day.empty" : "calendar.week.empty")"#))
  #expect(source.contains(#".overlay(alignment: .top)"#))
  #expect(source.contains(".padding(.leading, gutterWidth)"))
  #expect(source.contains(".padding(.horizontal, LorvexDesign.Spacing.l)"))
  #expect(components.contains("HStack(alignment: .center, spacing: LorvexDesign.Spacing.s)"))
  #expect(components.contains(".lineLimit(2)"))
  // The empty state spans the column band as a top banner, not a fixed-width
  // island floating over the middle of the week.
  #expect(!source.contains("emptyOverlayMaxWidth"))
  #expect(components.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
  #expect(components.contains(".background(.thinMaterial, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))"))
  #expect(components.contains(".buttonBorderShape(.capsule)"))
  #expect(!source.contains(".overlay(alignment: .center)"))
  #expect(!source.contains(".frame(width: 520, alignment: .leading)"))
  #expect(!source.contains(".background(.regularMaterial, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))"))
  #expect(!source.contains(".shadow(color: .black.opacity(0.06)"))
  #expect(components.contains(#""calendar.week.empty.title""#))
  #expect(components.contains(#""calendar.week.empty.description""#))
  #expect(components.contains(#""calendar.day.empty.title""#))
  #expect(components.contains(#""calendar.day.empty.description""#))
  #expect(components.contains(#"defaultValue: "Open Day""#))
  #expect(source.contains("createAt(target.date, target.minutes, 60)"))
  #expect(source.contains("calendar.component(.hour, from: now) + 1"))
  #expect(!source.contains("LorvexEmptyStatePanel("))
}

@Test
func calendarWeekGridHourLabelsDoNotFallbackToDateNow() throws {
  let source = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexApple/Views/CalendarWeekGridChrome.swift"),
    encoding: .utf8
  )

  #expect(source.contains("DateComponents(calendar: calendar)"))
  #expect(source.contains("components.year = 2001"))
  #expect(source.contains("guard let date = calendar.date(from: components)"))
  #expect(!source.contains("calendar.date(from: components) ?? Date()"))
}

@Test
func calendarWeekGridHintsSheetEditingForNonDraggableEditableBlocks() throws {
  let source = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexApple/Views/CalendarWeekGridEventBlock.swift"),
    encoding: .utf8
  )

  #expect(source.contains("if block.event.editable && !isEditable"))
  #expect(source.contains("inGridEditSheetHint(for: block)"))
  #expect(source.contains("block.event.isRecurring || block.event.supportsScopedMutation"))
  #expect(source.contains("? \"repeat.circle.fill\" : \"pencil.circle.fill\""))
  #expect(source.contains("calendar.weekgrid.editSheetHint"))
  #expect(source.contains("Recurring and multi-day events cannot be dragged or resized in the calendar grid."))
}

private func packageRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
