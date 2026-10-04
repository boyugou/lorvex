import LorvexCore
@testable import LorvexMobile
import SwiftUI
import Testing

@MainActor
@Test
func mobileRootViewCanBeInstantiatedFromStore() async throws {
  // The store-backed root is the production mobile entry point on iOS and
  // iPadOS.
  _ = LorvexMobileStoreRootView(store: MobileStore(core: try await makeSeededInMemoryCore()))
}

@MainActor
@Test
func mobileSystemEntrypointModifierReturnsView() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore())
  _ = Text("mobile shell").lorvexMobileSystemEntrypoints(store: store)
}

@MainActor
@Test
func mobileTaskDetailSheetsUseNativePresentationChrome() throws {
  let source = try mobileSourceFile("Sources/LorvexMobile/MobileStoreTaskDetailView.swift")

  // The recurrence editor is a dense form, so it opens at full height.
  #expect(source.contains(".mobileFullEditorSheetPresentation()"))

  // Detents + drag indicator are standardized in the shared editor-presentation modifiers.
  let presentation = try mobileSourceFile("Sources/LorvexMobile/MobileEditorSheetPresentation.swift")
  #expect(presentation.contains("[.medium, .large]"))
  #expect(presentation.contains("[.large]"))
  #expect(presentation.contains(".presentationDragIndicator(.visible)"))
}

@MainActor
@Test
func mobileSheetsShareOnePresentationThatOpensFullHeightAtAccessibilitySizes() throws {
  // A half-height sheet shows too little of its content once text is at an
  // accessibility size, so the one shared presentation reads the text size and
  // opens at large only there; every sheet that picks detents goes through it
  // instead of setting its own.
  let presentation = try mobileSourceFile("Sources/LorvexMobile/MobileEditorSheetPresentation.swift")
  #expect(presentation.contains("isAccessibilitySize"))

  let sheets = [
    "MobileStoreCaptureSheet", "MobileTodayScheduleSheet", "MobileTaskFieldEditor",
    "MobileStoreCreateListSheet", "MobileStoreEditListSheet", "MobileStoreMemoryEditorSheet",
    "MobileStoreMemoryComposerSheet", "MobileHabitReminderList", "MobileDependencyField",
  ]
  for name in sheets {
    let source = try mobileSourceFile("Sources/LorvexMobile/\(name).swift")
    #expect(!source.contains(".presentationDetents("), "\(name) takes its detents from the shared presentation")
    #expect(source.contains("EditorSheetPresentation("), "\(name) uses the shared presentation")
  }
}

@MainActor
@Test
func mobileEditorSheetsTitleThemselvesInlineAndDenseFormsOpenFullHeight() throws {
  // A create or edit sheet carries its title inline between Cancel and the
  // confirm button (mobileSheetTitle sets the inline display), so a large
  // title does not take a line of a short sheet.
  let sheets = [
    "MobileStoreCreateHabitSheet", "MobileStoreEditHabitSheet",
    "MobileStoreCreateListSheet", "MobileStoreEditListSheet",
    "MobileStoreCreateCalendarEventSheet", "MobileStoreEditCalendarEventSheet",
    "MobileStoreMemoryEditorSheet", "MobileTaskEditSheet",
  ]
  for name in sheets {
    let source = try mobileSourceFile("Sources/LorvexMobile/\(name).swift")
    #expect(source.contains(".mobileSheetTitle("), "\(name) titles itself inline")
  }
  let sheetTitle = try mobileSourceFile("Sources/LorvexMobile/MobileSheetTitle.swift")
  #expect(sheetTitle.contains(".navigationBarTitleDisplayMode(.inline)"))

  // The forms with many fields (a habit, an event, a task) open at full height
  // instead of a half-height detent that hides most of them.
  let dense = [
    "MobileStoreCreateHabitSheet", "MobileStoreEditHabitSheet",
    "MobileStoreCreateCalendarEventSheet", "MobileStoreEditCalendarEventSheet",
    "MobileTaskEditSheet",
  ]
  for name in dense {
    let source = try mobileSourceFile("Sources/LorvexMobile/\(name).swift")
    #expect(source.contains(".mobileFullEditorSheetPresentation()"), "\(name) opens at full height")
  }
}

@MainActor
@Test
func mobileListAndHabitSheetsLeadWithTheCreationHeader() throws {
  // A list or habit sheet opens on the live-preview header (icon tile, name,
  // second line) and keeps its icon and color choices behind the tile, so the
  // swatch and icon grids never take rows of the form.
  let headers = [
    ("MobileStoreCreateListSheet", "MobileListSheetHeader("),
    ("MobileStoreEditListSheet", "MobileListSheetHeader("),
    ("MobileStoreCreateHabitSheet", "MobileHabitSheetHeader("),
    ("MobileStoreEditHabitSheet", "MobileHabitSheetHeader("),
  ]
  for (name, header) in headers {
    let source = try mobileSourceFile("Sources/LorvexMobile/\(name).swift")
    #expect(source.contains(header), "\(name) leads with its creation header")
    #expect(!source.contains("MobileIconColorPicker("), "\(name) keeps icon and color behind the tile")
  }
  for name in ["MobileListSheetHeader", "MobileHabitSheetHeader"] {
    let source = try mobileSourceFile("Sources/LorvexMobile/\(name).swift")
    #expect(source.contains("MobileCreationHeader("), "\(name) builds on the shared header")
  }
  let header = try mobileSourceFile("Sources/LorvexMobile/MobileCreationHeader.swift")
  #expect(header.contains(".popover("), "the tile opens the icon and color choices in a popover")
  #expect(header.contains(".presentationCompactAdaptation(.popover)"), "the popover stays a popover on iPhone")

  // The swatch and icon cells have a fixed size: the picker caps its text size
  // so accessibility sizes cannot make the glyphs overlap, and each swatch is a
  // 44-point-high touch target.
  let picker = try mobileSourceFile("Sources/LorvexMobile/MobileIconColorPicker.swift")
  #expect(picker.contains(".dynamicTypeSize(...DynamicTypeSize.xxxLarge)"))
  #expect(picker.contains(".frame(maxWidth: .infinity, minHeight: 44)"))
}

@MainActor
@Test
func mobileTaskFieldPickersShowPriorityColorsAndListTiles() throws {
  // The priority choices carry the same flag colors as a task row, and the
  // list choices carry the same icon tiles as the Tasks home, so a choice is
  // recognized by its look as well as its name.
  let source = try mobileSourceFile("Sources/LorvexMobile/MobileTaskFieldEditor.swift")
  #expect(source.contains(".foregroundStyle(priority.priorityTint)"))
  #expect(source.contains("MobileIconTile("))
}

@MainActor
@Test
func mobileDayEditorMarksNoDayWhileTheFieldIsEmpty() throws {
  // A single-date picker always shows a selected day (today, for an empty
  // field), and tapping that day changes nothing, so an empty planned, due, or
  // hide-until field would look set and ignore a tap on today. The iOS editor
  // draws its month in a multiple-selection calendar that can show no day, and
  // reads every change through the shared single-day rules.
  let source = try mobileSourceFile("Sources/LorvexMobile/MobileTaskFieldEditor.swift")
  #expect(source.contains("MultiDatePicker("))
  #expect(source.contains("LorvexTaskFieldChoices.calendarSelection("))
  #expect(source.contains("LorvexTaskFieldChoices.day("))
}

@MainActor
@Test
func mobileFieldEditorsDrawTheirQuickChoicesAsSelectableChips() throws {
  // The quick days and the length presets are one-tap choices that read as a
  // set: the current one is filled with the accent and the rest stay neutral
  // with primary text, instead of gray text on a gray capsule.
  let editor = try mobileSourceFile("Sources/LorvexMobile/MobileTaskFieldEditor.swift")
  let uses = editor.components(separatedBy: "MobileFieldChip(").count - 1
  #expect(uses == 2, "the day editor and the length editor each draw their choices as chips")
  #expect(!editor.contains(".tint(.secondary)"))

  let chip = try mobileSourceFile("Sources/LorvexMobile/MobileFieldChip.swift")
  #expect(chip.contains(".borderedProminent"))
  #expect(chip.contains(".tint(.primary)"))
  #expect(chip.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
}

@MainActor
@Test
func handDrawnNotesPlaceholdersFollowThePlatformPlaceholderColor() throws {
  // The notes editors draw their placeholder over a text view, so it takes the
  // platform's placeholder color like the system field beside it; the
  // hierarchical tertiary style stays near 1.8:1 under Increase Contrast while
  // the system placeholder darkens to about 4.5:1.
  let editors = [
    "Sources/LorvexMobile/MobilePlainTextEditor.swift",
    "Sources/LorvexApple/Views/LorvexPlainTextEditor.swift",
  ]
  for path in editors {
    let source = try mobileSourceFile(path)
    #expect(source.contains(".foregroundStyle(LorvexDesign.Palette.placeholderText)"), "\(path)")
    #expect(!source.contains(".foregroundStyle(.tertiary)"), "\(path)")
  }
}

@MainActor
@Test
func mobileTaskEditSheetChoosesTheEstimateInsteadOfTypingIt() throws {
  // The estimate is a row that opens the How Long editor's ring and chips,
  // because a bare numeric field names no unit and its keyboard Done would
  // save the whole task.
  let source = try mobileSourceFile("Sources/LorvexMobile/MobileTaskEditSheet.swift")
  #expect(source.contains("MobileTaskLengthEditor("))
  #expect(!source.contains(".numberPad"))
  #expect(!source.contains("mobileKeyboardDoneToolbar"))
}

@MainActor
@Test
func mobileHabitSheetsSetTheDailyGoalWithAStepper() throws {
  // The per-day goal is a stepper row that reads as a sentence ("3 times a
  // day"), never a bare number field.
  for name in ["MobileStoreCreateHabitSheet", "MobileStoreEditHabitSheet"] {
    let source = try mobileSourceFile("Sources/LorvexMobile/\(name).swift")
    #expect(source.contains("MobileHabitGoalSection("), "\(name) uses the goal stepper section")
    #expect(!source.contains("targetCountText"), "\(name) does not edit the goal as free text")
  }
  let section = try mobileSourceFile("Sources/LorvexMobile/MobileHabitGoalSection.swift")
  #expect(section.contains("Stepper("), "the goal is edited with a stepper")
}

@MainActor
@Test
func mobileNameAndTitleFieldsWrapInsteadOfTruncating() throws {
  // A long list, habit, task, or event name stays fully visible while it is edited:
  // the field has a vertical axis, so it wraps, and Return still moves on as
  // the Next key. The list and habit headers also wrap their second line.
  let expectedAxes = [
    ("MobileListSheetHeader", 2),
    ("MobileHabitSheetHeader", 2),
    ("MobileTaskEditSheet", 1),
    ("MobileStoreCreateCalendarEventSheet", 2),
    ("MobileStoreEditCalendarEventSheet", 2),
  ]
  for (name, count) in expectedAxes {
    let source = try mobileSourceFile("Sources/LorvexMobile/\(name).swift")
    let axes = source.components(separatedBy: "axis: .vertical").count - 1
    #expect(axes >= count, "\(name) wraps its name or title field")
  }
}

@MainActor
@Test
func mobileTodayShowsHabitsAndEventsOnlyWhenLoaded() throws {
  let source = try mobileSourceFile("Sources/LorvexMobile/MobileStoreTodayView.swift")
  let page = try mobileSourceFile("Sources/LorvexMobile/MobileTodayPage.swift")
  let schedule = try mobileSourceFile("Sources/LorvexMobile/MobileTodayScheduleSheet.swift")

  // Today never fabricates empty arrays: habits render only when their data is
  // loaded and, once the habits resting today are left out, non-empty, so a
  // clear day reads as one calm composed state rather than a stack of empty
  // sections.
  #expect(!page.contains("store.habits?.habits ?? []"))
  #expect(
    page.contains(
      "if let habits = store.habits?.habits.listed(on: store.logicalTodayString), !habits.isEmpty"))
  // The schedule list draws today's events and timed tasks as one timeline
  // (events filtered to the logical day, not the raw multi-day window), and
  // its empty line only when that timeline has nothing to draw.
  #expect(schedule.contains("let drawsRows = rows.contains { $0.kind != .now }"))
  #expect(schedule.contains("items: rows"))
  let calmState = try mobileSourceFile("Sources/LorvexMobile/MobileStoreTodayCalmState.swift")
  #expect(calmState.contains("calendarTimeline?.eventsOccurring(on: logicalTodayString)"))
  // Lists were intentionally removed from Today — they live in their own destination,
  // not as a feature-dump section here.
  #expect(!source.contains("store.lists"))
  #expect(!page.contains("store.lists"))
}

@MainActor
@Test
func mobileTodayUsesPullToRefreshAndLeavesCaptureToTheTabBar() throws {
  let source = try mobileSourceFile("Sources/LorvexMobile/MobileStoreTodayView.swift")

  #expect(source.contains(".refreshable { await store.refresh() }"))
  #expect(source.contains(".toolbar"))
  // On iPhone capture is the tab bar's round + on every tab, so Today's own
  // bar carries no second capture button.
  #expect(!source.contains(#""today.toolbar.capture""#))
  #expect(!source.contains(#""today.refresh""#))
  let root = try mobileSourceFile("Sources/LorvexMobile/LorvexMobileStoreRootView.swift")
  #expect(root.contains("Tab(value: MobileTabBarItem.capture, role: .search)"))
  #expect(root.contains("case .capture: store.isPresentingCapture = true"))
  #expect(root.contains(#""today.capture""#))
}

@MainActor
@Test
func mobileSheetsTitleThemselvesThroughTheFittingSheetTitle() throws {
  // A sheet's Cancel and confirm buttons leave its inline title little room,
  // and a long translation is cut short there. Every sheet with a Cancel
  // button draws its title through mobileSheetTitle, which steps down a text
  // style and wraps onto two lines instead. The habit reminder-time sheet and
  // the data import preview keep the system's large title, which has a line
  // of its own and so never competes with the buttons.
  let largeTitled: Set<String> = ["MobileHabitReminderList.swift", "MobileStoreDataImportSection.swift"]
  let directory = try mobileSourceRoot().appendingPathComponent("Sources/LorvexMobile")
  let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    .filter { $0.hasSuffix(".swift") && !largeTitled.contains($0) }
    .sorted()
  var sheets = 0
  for name in names {
    let source = try mobileSourceFile("Sources/LorvexMobile/\(name)")
    guard source.contains("ToolbarItem(placement: .cancellationAction)") else { continue }
    sheets += 1
    #expect(source.contains(".mobileSheetTitle("), "\(name) titles its sheet with mobileSheetTitle")
  }
  #expect(sheets >= 14, "the sheet scan found the sheets")

  let title = try mobileSourceFile("Sources/LorvexMobile/MobileSheetTitle.swift")
  #expect(title.contains("ToolbarItem(placement: .principal)"))
  #expect(title.contains("ViewThatFits(in: .horizontal)"))
}

private func mobileSourceRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}

private func mobileSourceFile(_ relativePath: String) throws -> String {
  let url = mobileSourceRoot().appendingPathComponent(relativePath)
  return try String(contentsOf: url, encoding: .utf8)
}
