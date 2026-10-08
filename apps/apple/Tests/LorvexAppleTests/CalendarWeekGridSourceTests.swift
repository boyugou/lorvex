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

  #expect(source.contains("enum CalendarEventBlockMetrics"))
  // No view-level height floor: the model's drawn end carries the minimum, so
  // a short block never runs under the one that starts right after it.
  #expect(!source.contains("minimumHeight"))
  #expect(source.contains("static let accentRailWidth: CGFloat = 2.5"))
  #expect(source.contains("static let activeShadowRadius: CGFloat = 7"))
  // The block's text is arranged by the room it measures, not by height
  // thresholds that assume Latin line heights.
  #expect(source.contains("LorvexCalendarBlockText("))
  #expect(!source.contains("HeightThreshold"))
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

/// Overlap can split a lane too narrow for a word. Both block kinds then draw
/// the shared compact title, which fits the longest word or draws nothing,
/// instead of letting the title break letter by letter, and the tooltip names
/// the block.
@Test
func calendarWeekGridBlocksGoCompactInNarrowLanes() throws {
  for name in ["CalendarWeekGridEventBlock", "CalendarWeekGridTaskBlock"] {
    let source = try String(
      contentsOf: packageRoot().appending(path: "Sources/LorvexApple/Views/\(name).swift"),
      encoding: .utf8
    )
    #expect(source.contains("laneWidth < LorvexDesign.CalendarMetrics.compactLaneWidth"))
    #expect(source.contains("LorvexCalendarCompactBlockTitle("))
    #expect(source.contains(".help(isCompact ? label : \"\")"))
  }
}

/// The previous and next buttons step with ⌘ and an arrow key, bound through
/// `lorvexStepShortcut` so the key follows the chevron in a right-to-left
/// layout (`LorvexLayoutDirectionTests` pins the mapping).
@Test
func calendarNavigationButtonsExposeCommandArrowShortcuts() throws {
  let source = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexApple/Views/CalendarWorkspaceNavigationBar.swift"),
    encoding: .utf8
  )

  #expect(source.contains(".lorvexStepShortcut(.backward)"))
  #expect(source.contains(".lorvexStepShortcut(.forward)"))
  #expect(!source.contains(".keyboardShortcut(.leftArrow"))
  #expect(!source.contains(".keyboardShortcut(.rightArrow"))
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
  #expect(workspace.contains(".onChange(of: visiblePeriod)"))
  #expect(model.contains(#""calendar.mode.day""#))
  #expect(model.contains(#""calendar.mode.week""#))
  #expect(model.contains(#""calendar.mode.month""#))
  #expect(nav.contains("ForEach(CalendarPresentationMode.allCases"))
  #expect(!model.contains(#""calendar.mode.list""#))
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
  #expect(source.contains("overflowPopover(blocks: hidden, taskBlocks: hiddenTasks)"))
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

  #expect(grid.contains("nowLine(now: LorvexPreviewClock.now(in: calendar, tick: context.date), isToday: isToday(day.date))"))
  #expect(
    !grid.contains(
      "if isToday(day.date) {\n          TimelineView(.periodic(from: .now, by: 60)) { context in\n            nowLine("
    ))
  #expect(chrome.contains("func nowLine(now: Date, isToday: Bool)"))
  #expect(chrome.contains("Color.secondary.opacity(0.22)"))
  #expect(chrome.contains("let thickness: CGFloat = isToday ? 1.5 : 1"))
  #expect(chrome.contains("Rectangle().fill(lineColor).frame(height: thickness)"))
}

@Test
func calendarWeekGridLeavesAnEmptyRangeBareUnlessAccessIsOff() throws {
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
  #expect(source.contains("columns.allSatisfy(\\.isEmpty)"))
  // An empty day or week is a bare grid, like the month: no banner restating
  // the empty hours, and no create button beside the toolbar's.
  #expect(!source.contains("CalendarWeekEmptyOverlay"))
  #expect(!components.contains("CalendarWeekEmptyOverlay"))
  #expect(!source.contains("emptyWeekCreateTarget"))
  #expect(!components.contains(#""calendar.week.empty.title""#))
  #expect(!components.contains(#""calendar.day.empty.title""#))
  #expect(!source.contains("LorvexEmptyStatePanel("))
  // A blocked-access empty grid still says why it is empty, as a top banner
  // across the column band.
  #expect(source.contains("if isEmptyWeek(columns), EventKitAuthorizationHelper().needsSettingsRecovery {"))
  #expect(source.contains("CalendarWeekAuthorizeOverlay()"))
  #expect(source.contains(#".overlay(alignment: .top)"#))
  #expect(source.contains(".padding(.leading, gutterWidth)"))
  #expect(components.contains("struct CalendarWeekAuthorizeOverlay: View"))
  #expect(components.contains(#".accessibilityIdentifier("calendar.week.unauthorized")"#))
  #expect(components.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
  #expect(components.contains(".background(.thinMaterial, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))"))
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

@Test("The now line runs under the opaque blocks and its dot above them")
func calendarNowLineRunsUnderOpaqueBlocks() throws {
  let root = packageRoot()
  // zIndex, not declaration order, stacks these layers: the blocks sit at 1
  // (a selected or dragged macOS block at 2), the line stays at 0, and the dot
  // is lifted above every block.
  for (path, dotLayer) in [
    ("Sources/LorvexApple/Views/CalendarWeekGridView.swift", ".zIndex(3)"),
    ("Sources/LorvexMobile/MobileCalendarDayColumn.swift", ".zIndex(2)"),
  ] {
    let source = try String(contentsOf: root.appending(path: path), encoding: .utf8)
    let line = try #require(source.range(of: "nowLine(now:"))
    #expect(!source[line.upperBound...].prefix(200).contains(".zIndex("), "\(path) lifts the now line")
    let dot = try #require(source.range(of: "nowDot(now: LorvexPreviewClock"))
    #expect(
      source[dot.upperBound...].prefix(200).contains(dotLayer),
      "\(path) leaves the now dot under the blocks")
  }
  for (path, opaqueFill) in [
    ("Sources/LorvexApple/Views/CalendarWeekGridEventBlock.swift", ".lorvexOpaqueTintBackground("),
    ("Sources/LorvexApple/Views/CalendarWeekGridTaskBlock.swift", "hidesContentBeneath: true"),
    ("Sources/LorvexMobile/MobileCalendarEventBlock.swift", ".lorvexOpaqueTintBackground("),
    ("Sources/LorvexMobile/MobileCalendarTaskBlock.swift", "hidesContentBeneath: true"),
  ] {
    let source = try String(contentsOf: root.appending(path: path), encoding: .utf8)
    #expect(source.contains(opaqueFill), "\(path) fills its block see-through")
    #expect(source.contains(".zIndex("), "\(path) no longer lifts its block above the now line")
  }
}

@Test("Every task placement in the week grid goes through planTasks")
func calendarWeekGridPlansTasksThroughOneStoreAction() throws {
  let root = packageRoot()
  let grid = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWeekGridView.swift"),
    encoding: .utf8)
  let chrome = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWeekGridChrome.swift"),
    encoding: .utf8)
  let gestures = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWeekGridGestures.swift"),
    encoding: .utf8)
  let taskBlock = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWeekGridTaskBlock.swift"),
    encoding: .utf8)

  // The time axis takes drops through a delegate, which is the only SwiftUI
  // drop API that reports where the pointer is.
  #expect(grid.contains(".onDrop("))
  #expect(grid.contains("of: [.lorvexTask]"))
  #expect(grid.contains("TaskTimeDropDelegate("))
  #expect(grid.contains("time: .start(startMinute)"))
  // The all-day strip, the block drag, and the pills' menu items share the action.
  #expect(chrome.contains("time: .dayOnly"))
  #expect(chrome.contains("time: .unchanged"))
  #expect(gestures.contains("store.planTasks("))
  #expect(chrome.contains("store.planTasks("))
  // A finished task's block does not move; its block carries no drag gesture.
  let gesture = try #require(taskBlock.range(of: ".gesture("))
  let gestureBody = taskBlock[gesture.upperBound...].prefix(160)
  #expect(gestureBody.contains("block.isDone"))
  #expect(gestureBody.contains("? nil"))
  #expect(gestureBody.contains("taskMoveGesture("))
  #expect(taskBlock.contains("planLaterButtons(for: block.task"))
  // SwiftUI reports the pointer over the column once more while a drop completes,
  // so the indicator is cleared after the payload has loaded, not only on release.
  let delegate = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWeekGridTimeDrop.swift"),
    encoding: .utf8)
  let load = try #require(delegate.range(of: "loadTransferable(type: LorvexTaskRef.self)"))
  #expect(delegate[load.upperBound...].prefix(400).contains("hover(nil)"))
  // The earlier one-purpose action is gone.
  for source in [grid, chrome, gestures, taskBlock] {
    #expect(!source.contains("rescheduleScheduledTask"))
  }
}

@Test("Moving and resizing an event pass the window's undo manager, so ⌘Z puts it back")
func calendarWeekGridEventGesturesRegisterUndo() throws {
  let gestures = try String(
    contentsOf: packageRoot().appending(path: "Sources/LorvexApple/Views/CalendarWeekGridGestures.swift"),
    encoding: .utf8)
  // Move, resize at the bottom edge, and resize at the top edge.
  let calls = gestures.components(separatedBy: "store.rescheduleCalendarEvent(").dropFirst()
  #expect(calls.count == 3)
  for call in calls {
    #expect(call.prefix(160).contains("undoManager: undoManager"))
  }
}

@Test("A timed task's block resizes from both edges, never over its completion circle")
func calendarWeekGridTaskBlocksResizeFromTheirEdges() throws {
  let root = packageRoot()
  let taskBlock = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWeekGridTaskBlock.swift"),
    encoding: .utf8)
  let gestures = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWeekGridGestures.swift"),
    encoding: .utf8)

  // Both edges carry a grip, a finished task's block carries neither, and the
  // grips start past the circle so its upper half still completes the task.
  #expect(taskBlock.contains("let isResizable = !block.isDone"))
  #expect(taskBlock.contains("taskResizeGesture(for: block, dayIndex: dayIndex, edge: .start)"))
  #expect(taskBlock.contains("taskResizeGesture(for: block, dayIndex: dayIndex, edge: .end)"))
  #expect(taskBlock.contains("CalendarEventBlockMetrics.taskCircleInset"))
  #expect(taskBlock.components(separatedBy: "leadingInset: gripInset").count == 3)
  // A resize sets the task's time through the one placement action, so ⌘Z
  // restores it, and leaves the estimate alone.
  let resize = try #require(gestures.range(of: "func taskResizeGesture("))
  let body = gestures[resize.upperBound...].prefix(1_400)
  #expect(body.contains("store.planTasks("))
  #expect(body.contains("time: .exactly(resized)"))
  #expect(body.contains("undoManager: undoManager"))
  #expect(!body.contains("estimat"))
  // Events and tasks resize through the same pure function.
  #expect(gestures.components(separatedBy: "CalendarGridMove.resized(").count == 4)
  // The inset narrows the hit area: it is applied after the gesture, since a
  // padding applied before the content shape would be hit too.
  let eventBlock = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/CalendarWeekGridEventBlock.swift"),
    encoding: .utf8)
  let handle = try #require(eventBlock.range(of: "func resizeHandle("))
  let handleBody = String(eventBlock[handle.upperBound...].prefix(1_400))
  let gestureAt = try #require(handleBody.range(of: ".gesture(gesture)"))
  let paddingAt = try #require(handleBody.range(of: ".padding(.leading, leadingInset)"))
  #expect(gestureAt.lowerBound < paddingAt.lowerBound)
}
