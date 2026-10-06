import Carbon.HIToolbox
import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// MARK: - Shortcut presets

@Test
func quickCaptureIsOffUntilTheUserChoosesAShortcut() {
  #expect(QuickCaptureShortcut.default == .off)
  #expect(QuickCaptureShortcut.off.chord == nil)
}

@Test
func everyQuickCapturePresetIsADistinctModifierChordWithSpace() throws {
  let chords = try QuickCaptureShortcut.allCases.filter { $0 != .off }.map { try #require($0.chord) }

  #expect(chords.count == QuickCaptureShortcut.allCases.count - 1)
  #expect(chords.allSatisfy { $0.keyCode == UInt32(kVK_Space) })
  // A bare Space would swallow typing everywhere, so every preset carries a
  // modifier, and no two presets are the same chord.
  #expect(chords.allSatisfy { $0.modifiers != 0 })
  #expect(Set(chords.map(\.modifiers)).count == chords.count)
  #expect(QuickCaptureShortcut.controlOptionSpace.chord?.modifiers == UInt32(controlKey | optionKey))
  #expect(QuickCaptureShortcut.controlSpace.chord?.modifiers == UInt32(controlKey))
  #expect(QuickCaptureShortcut.optionSpace.chord?.modifiers == UInt32(optionKey))
  #expect(QuickCaptureShortcut.controlShiftSpace.chord?.modifiers == UInt32(controlKey | shiftKey))
}

@Test
func quickCaptureRawValuesAreTheStoredPreferenceValues() {
  // The raw value is what UserDefaults keeps, so renaming a case would silently
  // reset every user's choice.
  #expect(
    QuickCaptureShortcut.allCases.map(\.rawValue) == [
      "off", "controlOptionSpace", "controlSpace", "optionSpace", "controlShiftSpace",
    ])
}

@Test
func quickCaptureTitlesWriteTheChordTheWayMacOSDoes() {
  #expect(QuickCaptureShortcut.off.localizedTitle == "Off")
  #expect(QuickCaptureShortcut.controlOptionSpace.localizedTitle == "⌃⌥Space")
  #expect(QuickCaptureShortcut.controlSpace.localizedTitle == "⌃Space")
  #expect(QuickCaptureShortcut.optionSpace.localizedTitle == "⌥Space")
  #expect(QuickCaptureShortcut.controlShiftSpace.localizedTitle == "⌃⇧Space")
}

// MARK: - Setting

@MainActor
@Test
func theQuickCaptureShortcutIsStoredAndResetWithTheOtherPreferences() {
  let suiteName = "LorvexAppleTests.quick-capture-shortcut.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let settings = AppSettingsStore(defaults: defaults, environment: [:])
  #expect(settings.quickCaptureShortcut == .off)
  #expect(settings.quickCaptureShortcutIsAvailable)

  settings.quickCaptureShortcut = .controlShiftSpace
  let restored = AppSettingsStore(defaults: defaults, environment: [:])
  #expect(restored.quickCaptureShortcut == .controlShiftSpace)

  restored.resetToDefaults()
  #expect(restored.quickCaptureShortcut == .off)
  #expect(AppSettingsStore(defaults: defaults, environment: [:]).quickCaptureShortcut == .off)
}

@MainActor
@Test
func aStoredShortcutThisBuildDoesNotKnowReadsAsOff() {
  let suiteName = "LorvexAppleTests.quick-capture-unknown.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }
  defaults.set("hyperSpace", forKey: AppSettingsStore.Key.quickCaptureShortcut)

  #expect(AppSettingsStore(defaults: defaults, environment: [:]).quickCaptureShortcut == .off)
}

// MARK: - Model

@MainActor
private final class CallCounter {
  var count = 0
}

/// Holds a core write until released, so a test can act while a capture is
/// mid-write.
private actor WriteGate {
  private var held = false
  private var released = false
  private var heldContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func hold() async {
    held = true
    heldContinuation?.resume()
    heldContinuation = nil
    if !released {
      await withCheckedContinuation { releaseContinuation = $0 }
    }
  }

  func waitUntilHeld() async {
    if held { return }
    await withCheckedContinuation { heldContinuation = $0 }
  }

  func release() {
    released = true
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

/// Polls the main actor until `condition` holds, for state that settles on a
/// later turn (observation callbacks, detached tasks). Returns as soon as the
/// condition holds; the ceiling is generous because a full test run queues
/// many tests on the main actor and each poll waits its turn. False on timeout.
@MainActor
private func settle(
  timeout: Duration = .seconds(120), until condition: @MainActor () -> Bool
) async -> Bool {
  let deadline = ContinuousClock.now + timeout
  while !condition() {
    if ContinuousClock.now > deadline { return false }
    try? await Task.sleep(for: .milliseconds(5))
  }
  return true
}

@MainActor
private func makeCaptureModel(
  core: any LorvexCoreServicing, hold: Duration = .milliseconds(1)
) async -> (store: AppStore, model: QuickCaptureModel) {
  let store = AppStore(core: core)
  await store.refresh()
  return (store, QuickCaptureModel(store: store, confirmationHold: hold))
}

@MainActor
@Test
func submittingALineWritesTheTaskAndShowsWhereItLanded() async throws {
  let (store, model) = await makeCaptureModel(core: try await makeSeededInMemoryCore())
  let finished = CallCounter()
  model.onFinish = { finished.count += 1 }
  model.prepare()
  model.text = "Call the caterer tomorrow"

  await model.submit()

  let open = try await store.core.listTasks(
    status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let created = try #require(open.tasks.first { $0.title == "Call the caterer" })
  // The window reads the line like every other capture field.
  #expect(created.plannedDate == (try store.storageDate(daysFromLogicalToday: 1)))
  let landedIn = try #require(store.lists?.lists.first { $0.id == created.listID })
  #expect(model.phase == .captured(listName: landedIn.displayName))
  #expect(model.text.isEmpty)
  #expect(finished.count == 1)
  // The window is the confirmation, so the main window gets no toast as well.
  #expect(store.toastMessage == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func theFanOutAfterAQuickCaptureStillRuns() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let (_, model) = await makeCaptureModel(core: core)
  let badgeReads = CallCounter()
  core.widgetStatsGate = { await MainActor.run { badgeReads.count += 1 } }
  model.text = "Fan-out check"

  await model.submit()

  // The fan-out is the badge's read among other work: it runs on its own time,
  // after the confirmation has been shown.
  #expect(await settle { badgeReads.count > 0 })
}

@MainActor
@Test
func aBlankQuickCaptureCreatesNothingAndStaysOpen() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let (_, model) = await makeCaptureModel(core: core)
  let finished = CallCounter()
  model.onFinish = { finished.count += 1 }
  model.text = "  \n "

  await model.submit()

  #expect(core.createdTaskTitles.isEmpty)
  #expect(model.phase == .editing)
  #expect(finished.count == 0)
}

@MainActor
@Test
func aSecondReturnWhileTheWriteIsUnderWayCreatesOneTask() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let gate = WriteGate()
  core.createTaskGate = { await gate.hold() }
  let (_, model) = await makeCaptureModel(core: core)
  model.text = "Return twice"

  let first = Task { await model.submit() }
  await gate.waitUntilHeld()
  await model.submit()
  await gate.release()
  await first.value

  #expect(core.createdTaskTitles == ["Return twice"])
}

@MainActor
@Test
func aFailedQuickCaptureKeepsTheLineShowsTheFailureAndRetries() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let (store, model) = await makeCaptureModel(core: core)
  let finished = CallCounter()
  model.onFinish = { finished.count += 1 }
  core.createTaskError = .validation(field: "title", message: "Injected capture failure.")
  model.text = "Pay the invoice"

  await model.submit()

  guard case .failed(let message) = model.phase else {
    Issue.record("expected a failed phase, got \(model.phase)")
    return
  }
  #expect(!message.isEmpty)
  #expect(model.text == "Pay the invoice")
  #expect(finished.count == 0)
  // The window explains the failure, so the main window's alert does not.
  #expect(store.errorMessage == nil)

  // Editing the line clears the failure; the retry goes through.
  core.createTaskError = nil
  model.text = "Pay the invoice today"
  #expect(model.phase == .editing)
  await model.submit()
  guard case .captured(let listName) = model.phase else {
    Issue.record("the retry should have been captured, got \(model.phase)")
    return
  }
  #expect(!listName.isEmpty)
  #expect(finished.count == 1)
  #expect(core.createdTaskTitles == ["Pay the invoice", "Pay the invoice"])
}

@MainActor
@Test
func aFailedQuickCaptureCanBeRetriedWithoutEditingTheLine() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let (_, model) = await makeCaptureModel(core: core)
  core.createTaskError = .validation(field: "title", message: "Injected capture failure.")
  model.text = "Same line again"
  await model.submit()
  #expect(model.phase != .editing)

  core.createTaskError = nil
  await model.submit()

  #expect(model.text.isEmpty)
  if case .captured = model.phase {} else { Issue.record("the retry should have captured") }
}

@MainActor
@Test
func aNewPresentationDuringTheConfirmationKeepsTheWindowOpen() async throws {
  // The confirmation is held for an hour so the test, not the clock, decides
  // when the user opens the window again; cancelling the submit ends the hold.
  let (_, model) = await makeCaptureModel(
    core: try await makeSeededInMemoryCore(), hold: .seconds(3600))
  let finished = CallCounter()
  model.onFinish = { finished.count += 1 }
  model.text = "Held open"

  let submit = Task { await model.submit() }
  #expect(await settle { model.phase != .editing })
  // The confirmation is showing when the user opens the window again.
  model.prepare()
  submit.cancel()
  await submit.value

  #expect(finished.count == 0)
  #expect(model.phase == .editing)
}

@MainActor
@Test
func aWriteFinishingAfterANewPresentationLeavesTheNewLineAlone() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let gate = WriteGate()
  core.createTaskGate = { await gate.hold() }
  let (_, model) = await makeCaptureModel(core: core)
  let finished = CallCounter()
  model.onFinish = { finished.count += 1 }
  model.text = "Slow first"

  let first = Task { await model.submit() }
  await gate.waitUntilHeld()
  // The window is dismissed and opened again while the first write is held.
  model.prepare()
  model.text = "Typed second"
  await gate.release()
  await first.value

  #expect(core.createdTaskTitles == ["Slow first"])
  #expect(model.text == "Typed second")
  #expect(model.phase == .editing)
  #expect(finished.count == 0)
}

@MainActor
@Test
func aFailureAfterTheWindowMovedOnIsLeftForTheMainWindowAlert() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let gate = WriteGate()
  core.createTaskGate = { await gate.hold() }
  core.createTaskError = .validation(field: "title", message: "Injected capture failure.")
  let (store, model) = await makeCaptureModel(core: core)
  model.text = "Lost unless surfaced"

  let first = Task { await model.submit() }
  await gate.waitUntilHeld()
  model.cancel()
  await gate.release()
  await first.value

  #expect(model.phase == .editing)
  #expect(store.errorMessage != nil)
}

@MainActor
@Test
func escapeThrowsTheDraftAwayAndAHalfTypedLineSurvivesADismissal() async throws {
  let (_, model) = await makeCaptureModel(core: try await makeSeededInMemoryCore())
  let finished = CallCounter()
  model.onFinish = { finished.count += 1 }

  // Clicking away dismisses the window without touching the model: the draft
  // is still there when the window comes back.
  model.prepare()
  model.text = "Half typed"
  model.prepare()
  #expect(model.text == "Half typed")

  // Escape says the user does not want the line.
  model.cancel()
  #expect(model.text.isEmpty)
  #expect(finished.count == 1)
  model.prepare()
  #expect(model.text.isEmpty)
}

@MainActor
@Test
func eachPresentationAndBecomingTheKeyWindowAskTheFieldForFocus() async throws {
  let (_, model) = await makeCaptureModel(core: try await makeSeededInMemoryCore())
  let before = model.focusRequest

  model.prepare()
  model.prepare()
  #expect(model.focusRequest == before + 2)

  // The window asks again once it is the key window.
  model.requestFocus()
  #expect(model.focusRequest == before + 3)
}

// MARK: - Controller

@MainActor
private final class FakeHotKey: GlobalHotKeyRegistering {
  var registered: [QuickCaptureShortcut] = []
  var acceptsChords = true
  private var handler: (@MainActor () -> Void)?

  func register(
    _ shortcut: QuickCaptureShortcut, handler: @escaping @MainActor () -> Void
  ) -> Bool {
    registered.append(shortcut)
    self.handler = handler
    return shortcut == .off || acceptsChords
  }

  func press() { handler?() }
}

@MainActor
private final class FakePresenter: QuickCapturePresenting {
  private(set) var isPresented = false
  private(set) var presentCount = 0
  private(set) var dismissCount = 0

  func present() {
    isPresented = true
    presentCount += 1
  }

  func dismiss() {
    isPresented = false
    dismissCount += 1
  }
}

@MainActor
private struct ControllerHarness {
  let settings: AppSettingsStore
  let model: QuickCaptureModel
  let hotKey = FakeHotKey()
  let presenter = FakePresenter()
  let controller: QuickCaptureController
  private let defaults: UserDefaults
  private let suiteName: String

  init(shortcut: QuickCaptureShortcut = .off) async throws {
    suiteName = "LorvexAppleTests.quick-capture-controller.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)!
    settings = AppSettingsStore(defaults: defaults, environment: [:])
    settings.quickCaptureShortcut = shortcut
    let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
    model = QuickCaptureModel(store: store, confirmationHold: .milliseconds(1))
    controller = QuickCaptureController(
      settings: settings, model: model, presenter: presenter, hotKey: hotKey)
  }

  func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
  }
}

@MainActor
@Test
func startingTheControllerRegistersTheChosenShortcut() async throws {
  let harness = try await ControllerHarness(shortcut: .optionSpace)
  defer { harness.tearDown() }

  harness.controller.start()

  #expect(harness.hotKey.registered == [.optionSpace])
  #expect(harness.settings.quickCaptureShortcutIsAvailable)
}

@MainActor
@Test
func theControllerFollowsTheSettingInBothDirections() async throws {
  let harness = try await ControllerHarness()
  defer { harness.tearDown() }
  harness.controller.start()
  #expect(harness.hotKey.registered == [.off])

  harness.settings.quickCaptureShortcut = .controlSpace
  #expect(await settle { harness.hotKey.registered == [.off, .controlSpace] })

  harness.settings.quickCaptureShortcut = .controlShiftSpace
  #expect(await settle { harness.hotKey.registered == [.off, .controlSpace, .controlShiftSpace] })

  // Off releases the chord.
  harness.settings.quickCaptureShortcut = .off
  #expect(
    await settle {
      harness.hotKey.registered == [.off, .controlSpace, .controlShiftSpace, .off]
    })
}

@MainActor
@Test
func aChordAnotherAppOwnsIsReportedAndClearedWhenTheChoiceChanges() async throws {
  let harness = try await ControllerHarness(shortcut: .controlOptionSpace)
  defer { harness.tearDown() }
  harness.hotKey.acceptsChords = false

  harness.controller.start()
  #expect(!harness.settings.quickCaptureShortcutIsAvailable)

  // Choosing Off needs no chord, so nothing is unavailable any more.
  harness.settings.quickCaptureShortcut = .off
  #expect(await settle { harness.settings.quickCaptureShortcutIsAvailable })

  // A free chord is accepted again.
  harness.hotKey.acceptsChords = true
  harness.settings.quickCaptureShortcut = .optionSpace
  #expect(await settle { harness.hotKey.registered.last == .optionSpace })
  #expect(harness.settings.quickCaptureShortcutIsAvailable)
}

@MainActor
@Test
func theShortcutOpensTheWindowAndPressingItAgainClosesIt() async throws {
  let harness = try await ControllerHarness(shortcut: .optionSpace)
  defer { harness.tearDown() }
  harness.controller.start()

  harness.hotKey.press()
  #expect(harness.presenter.isPresented)
  #expect(harness.presenter.presentCount == 1)

  harness.hotKey.press()
  #expect(!harness.presenter.isPresented)
  #expect(harness.presenter.dismissCount == 1)

  withExtendedLifetime(harness.controller) {}
}

@MainActor
@Test
func presentingResetsAFinishedCaptureAndShowsTheWindow() async throws {
  let harness = try await ControllerHarness()
  defer { harness.tearDown() }
  harness.model.text = "Finished before"
  await harness.model.submit()
  #expect(harness.model.phase != .editing)

  harness.controller.present()

  #expect(harness.presenter.isPresented)
  #expect(harness.model.phase == .editing)
}

@MainActor
@Test
func finishingACaptureOrPressingEscapeClosesTheWindow() async throws {
  let harness = try await ControllerHarness()
  defer { harness.tearDown() }
  harness.controller.present()
  harness.model.text = "Close me after"

  await harness.model.submit()
  #expect(!harness.presenter.isPresented)

  harness.controller.present()
  #expect(harness.presenter.isPresented)
  harness.model.cancel()
  #expect(!harness.presenter.isPresented)
}

@MainActor
@Test
func theMenuCommandAndThePaletteOpenTheWindowThroughTheRequestNotification() async throws {
  let harness = try await ControllerHarness()
  defer { harness.tearDown() }
  harness.controller.start()

  // The observer starts listening on the next turn; keep asking until the
  // window opens.
  let opened = await settle {
    NotificationCenter.default.post(name: QuickCaptureController.requestNotification, object: nil)
    return harness.presenter.presentCount > 0
  }

  #expect(opened)
  #expect(harness.presenter.isPresented)
  withExtendedLifetime(harness.controller) {}
}
