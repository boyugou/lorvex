import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexApple

@MainActor
@Test
func appStoreCreatesTaskThroughSharedCapturePath() async throws {
  let suiteName = "appStoreCreatesTaskThroughSharedCapturePath.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

  await store.refresh()
  store.selection = .tasks
  store.selectedTaskID = nil
  await store.captureLine("Captured from native quick capture")

  // Global capture files the thought in the inbox, undated, and leaves the user
  // exactly where they were: no navigation and no selection change, so the toast
  // is the confirmation that something happened.
  let open = try await store.core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let captured = try #require(
    open.tasks.first { $0.title == "Captured from native quick capture" })
  #expect(captured.plannedDate == nil)
  #expect(captured.dueDate == nil)
  #expect(!store.today.tasks.contains { $0.id == captured.id })
  #expect(store.selection == .tasks)
  #expect(store.selectedTaskID == nil)
  let landedIn = try #require(store.lists?.lists.first { $0.id == captured.listID })
  #expect(
    store.toastMessage
      == AppStore.captureToastMessage(count: 1, listName: landedIn.displayName))
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func aMultiLinePasteIsCapturedAsOneTaskWithAOneLineTitle() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let pasted = "Call the caterer\nabout the quote\r\ntomorrow"

  await store.captureLine(pasted)

  // A single-line field keeps the breaks of a paste; the task reads the line as
  // one line, details included, and keeps the text as typed for the assistant.
  let open = try await store.core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let created = try #require(open.tasks.first { $0.title == "Call the caterer about the quote" })
  let hasBreak = created.title.contains(where: \.isNewline)
  #expect(!hasBreak)
  #expect(created.plannedDate == (try store.storageDate(daysFromLogicalToday: 1)))
  #expect(created.rawInput == pasted)
  #expect(store.errorMessage == nil)
}

@Test
func captureTitleParserKeepsOnlyTrimmedNonEmptyLines() {
  #expect(
    CaptureTitleParser.titles(from: " first task \n\n\tsecond task\n ") == [
      "first task",
      "second task",
    ]
  )
}

@MainActor
@Test
func inlineInboxAddStaysOnCurrentSurface() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  store.selection = .tasks
  store.selectedTaskID = nil
  let selectionBefore = store.selectedTaskID

  await store.createInlineTask("  Inline all-tasks add  ", destination: .inbox)

  // The inline all-tasks quick-add lands the task in the inbox and stays in
  // place, so consecutive Returns keep adding without yanking the view. No toast
  // either: the workspace the user is looking at gains the row.
  let open = try await store.core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let created = try #require(open.tasks.first { $0.title == "Inline all-tasks add" })
  #expect(store.selection == .tasks)
  #expect(store.selectedTaskID == selectionBefore)
  #expect(store.selectedTaskID != created.id)
  #expect(store.toastMessage == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func requestQuickAddFocusBumpsTokenMonotonically() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  let start = store.quickAddFocusToken

  store.requestQuickAddFocus()
  store.requestQuickAddFocus()

  #expect(store.quickAddFocusToken == start + 2)
}

@MainActor
@Test
func inlineAddReadsDetailsOutOfTheTypedLine() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let list = try #require(store.orderedLists.first)
  let hashName = list.name.filter { $0.isLetter || $0.isNumber }
  let line = "Call the caterer tomorrow 25 min by friday !! #\(hashName) #food"

  let preview = store.quickAddPreview(line)
  #expect(preview.title == "Call the caterer")
  #expect(preview.words.map(\.id) == ["when", "length", "due", "list", "priority", "tag.food"])

  // A day written in the line overrides the Today destination's default day.
  await store.createInlineTask(line, destination: .today)

  #expect(store.errorMessage == nil)
  let open = try await store.core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let created = try #require(open.tasks.first { $0.title == "Call the caterer" })
  let parse = store.captureParse(line)
  let dueOffset = try #require(parse.dueDayOffset)
  #expect(created.plannedDate == (try store.storageDate(daysFromLogicalToday: 1)))
  #expect(created.dueDate == (try store.storageDate(daysFromLogicalToday: dueOffset)))
  #expect(created.estimatedMinutes == 25)
  #expect(created.priority == .p1)
  #expect(created.listID == list.id)
  #expect(created.tags == ["food"])
  #expect(created.rawInput == line)
}

@MainActor
@Test
func inlineAddWithoutDetailsKeepsTheDestinationDefaults() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  #expect(store.quickAddPreview("Water the plants") == .empty)
  await store.createInlineTask("Water the plants", destination: .today)

  let created = try #require(store.today.tasks.first { $0.title == "Water the plants" })
  #expect(created.plannedDate == (try store.storageDate(daysFromLogicalToday: 0)))
  #expect(created.rawInput == nil)
  #expect(created.priority == .p2)
}

/// Store state observed from inside the stub core's gates: the badge's read
/// in the post-create fan-out (`widgetStatsGate`) and, when the task
/// workspace is loaded, its reload through `listTasks` (`listTasksGate`).
@MainActor
private final class CaptureFanOutProbe {
  var busyFlags: [Bool] = []
  var feedbackSeen: [Bool] = []
  var toastSeen: [Bool] = []
}

@MainActor
@Test("global capture confirms before the fan-out and never raises the create flag")
func globalCaptureConfirmsBeforeFanOut() async throws {
  let feedback = RecordingFeedbackProvider()
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = AppStore(core: core, feedbackProvider: feedback)
  await store.refresh()
  let probe = CaptureFanOutProbe()
  core.widgetStatsGate = {
    await MainActor.run {
      probe.busyFlags.append(store.isCreating)
      probe.feedbackSeen.append(feedback.recorded.contains(.captureSubmitted))
      probe.toastSeen.append(store.toastMessage != nil)
    }
  }

  await store.captureLine("Gate probe capture")

  // The fan-out ends with a sync cycle that can run for as long as CloudKit
  // takes, so the capture must already be confirmed by the time the fan-out's
  // badge read runs.
  #expect(!probe.busyFlags.isEmpty)
  #expect(probe.busyFlags.allSatisfy { !$0 })
  #expect(probe.feedbackSeen.allSatisfy { $0 })
  #expect(probe.toastSeen.allSatisfy { $0 })
  #expect(store.isCreating == false)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test("inline adds typed back to back all land, in order, and never raise the create flag")
func inlineAddsTypedBackToBackAllLand() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = AppStore(core: core)
  await store.refresh()
  // A loaded workspace makes each commit's reconcile read through `listTasks`,
  // so the gates observe the flag during the commit as well as the fan-out.
  await store.loadTaskWorkspace()
  #expect(store.taskWorkspaceHasLoaded)
  let probe = CaptureFanOutProbe()
  let recordFlag: @Sendable () async -> Void = {
    await MainActor.run { probe.busyFlags.append(store.isCreating) }
  }
  core.listTasksGate = recordFlag
  core.widgetStatsGate = recordFlag

  // Two Returns before the first line has finished committing: the row stays
  // enabled (the flag never rises) and neither line is dropped. Main-actor
  // tasks start in the order they are created, as two keystrokes arrive;
  // `async let` children hop to the main actor in no guaranteed order.
  let first = Task { await store.createInlineTask("Back-to-back one", destination: .inbox) }
  let second = Task { await store.createInlineTask("Back-to-back two", destination: .inbox) }
  _ = await (first.value, second.value)

  let open = try await core.preview.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  #expect(open.tasks.contains { $0.title == "Back-to-back one" })
  #expect(open.tasks.contains { $0.title == "Back-to-back two" })
  #expect(core.createdTaskTitles == ["Back-to-back one", "Back-to-back two"])
  #expect(store.taskWorkspaceAllTasks.contains { $0.title == "Back-to-back two" })
  #expect(!probe.busyFlags.isEmpty)
  #expect(probe.busyFlags.allSatisfy { !$0 })
  #expect(store.isCreating == false)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func inlineAddWithOnlyAClockTimePlansTodayAtThatTime() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let line = "Dentist 4pm 45 min"

  // The span replaces the separate length word.
  #expect(store.quickAddPreview(line).words.map(\.id) == ["when", "time"])

  // The inbox destination leaves a dayless line undated, but a time needs a day.
  await store.createInlineTask(line, destination: .inbox)

  #expect(store.errorMessage == nil)
  let open = try await store.core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let created = try #require(open.tasks.first { $0.title == "Dentist" })
  #expect(created.plannedDate == (try store.storageDate(daysFromLogicalToday: 0)))
  #expect(created.plannedTime == (16 * 60)..<(16 * 60 + 45))
  #expect(created.estimatedMinutes == 45)
}

@MainActor
@Test
func inlineAddCreatesARepeatingTaskOnItsFirstOccurrence() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let line = "Water the plants every day"

  #expect(store.quickAddPreview(line).words.map(\.id) == ["repeats", "due"])

  await store.createInlineTask(line, destination: .inbox)

  #expect(store.errorMessage == nil)
  let open = try await store.core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let created = try #require(open.tasks.first { $0.title == "Water the plants" })
  #expect(created.recurrence?.freq == .daily)
  #expect(created.dueDate == (try store.storageDate(daysFromLogicalToday: 0)))
  #expect(created.plannedDate == nil)
}

@MainActor
@Test
func globalCaptureReadsDetailsLikeTheInlineRows() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  // The menu bar and the palette capture through one path: the line's day,
  // time and length become the task's fields and leave its title.
  await store.captureLine("Call the caterer tomorrow 3pm 20 min")

  #expect(store.errorMessage == nil)
  let open = try await store.core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let created = try #require(open.tasks.first { $0.title == "Call the caterer" })
  #expect(created.plannedDate == (try store.storageDate(daysFromLogicalToday: 1)))
  #expect(created.plannedTime == (15 * 60)..<(15 * 60 + 20))
  #expect(created.estimatedMinutes == 20)
  // Out of sight, so the toast names where it landed, and nothing navigates.
  let landedIn = try #require(store.lists?.lists.first { $0.id == created.listID })
  #expect(
    store.toastMessage == AppStore.captureToastMessage(count: 1, listName: landedIn.displayName))
}

@MainActor
@Test
func globalCaptureWithoutADayStaysUndated() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  await store.captureLine("  Renew the passport  ")

  let open = try await store.core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let created = try #require(open.tasks.first { $0.title == "Renew the passport" })
  #expect(created.plannedDate == nil)
  #expect(created.plannedTime == nil)
  #expect(created.dueDate == nil)
  #expect(!store.today.tasks.contains { $0.id == created.id })
}

@MainActor
@Test
func globalCaptureFilesTheTaskInTheListTheLineNames() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let named = try #require(store.orderedLists.first { !$0.isInbox })
  let hashName = named.name.filter { $0.isLetter || $0.isNumber }

  await store.captureLine("Pick up samples #\(hashName)")

  let open = try await store.core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let created = try #require(open.tasks.first { $0.title == "Pick up samples" })
  #expect(created.listID == named.id)
  #expect(store.toastMessage == AppStore.captureToastMessage(count: 1, listName: named.displayName))
}

@MainActor
@Test
func globalCaptureIsNotLostWhileAnotherCreateIsInFlight() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  // A list or habit sheet is mid-save and holds the shared create flag; a
  // capture typed in that window still lands instead of being dropped.
  store.isCreating = true
  await store.captureLine("Typed while a sheet saves")

  let open = try await store.core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  #expect(open.tasks.contains { $0.title == "Typed while a sheet saves" })
  #expect(store.isCreating, "the capture must leave the other create's flag alone")
}

@MainActor
@Test
func globalCapturesTypedBackToBackAllLandInOrder() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = AppStore(core: core)
  await store.refresh()

  let first = Task { await store.captureLine("Menu bar one") }
  let second = Task { await store.captureLine("Menu bar two") }
  let inline = Task { await store.createInlineTask("Row three", destination: .inbox) }
  _ = await (first.value, second.value, inline.value)

  // One queue serves the global capture and the inline rows.
  #expect(core.createdTaskTitles == ["Menu bar one", "Menu bar two", "Row three"])
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func aBlankGlobalCaptureCreatesNothing() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = AppStore(core: core)
  await store.refresh()

  await store.captureLine("   \n ")

  #expect(core.createdTaskTitles.isEmpty)
  #expect(store.toastMessage == nil)
}
