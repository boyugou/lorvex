import Foundation
import Testing

@testable import LorvexApple
@testable import LorvexCore

/// The habit inspector's name and encouragement save when their field loses
/// focus, which ⌘Q does not wait for: Quit writes the text a field holds and
/// waits for the writes already running.
@MainActor
@Suite("Habit field draft at Quit")
struct AppStoreHabitFieldDraftTests {
  private func makeStore<Core: LorvexCoreServicing>(_ core: Core) async throws
    -> (AppStore, LorvexHabit)
  {
    let habit = try await core.createHabit(name: "Stretch", cue: "Loosen up", targetCount: 1)
    let store = AppStore(core: core)
    await store.refresh()
    return (store, habit)
  }

  private func stored(_ id: LorvexHabit.ID, in core: some LorvexCoreServicing) async throws
    -> LorvexHabit
  {
    try #require(try await core.loadHabits(date: "2026-05-23").habits.first { $0.id == id })
  }

  @Test("Quit writes the name and the encouragement being typed")
  func quitWritesTheTypedText() async throws {
    let core = try await makeSeededInMemoryCore()
    let (store, habit) = try await makeStore(core)

    store.noteHabitFieldDraft(HabitFieldDraft(habit: habit, field: .name, text: "Stretch twice "))
    #expect(store.hasPendingAutosaveDraftForTermination)
    #expect(await store.flushPendingAutosaveDraftsForTermination())
    #expect(try await stored(habit.id, in: core).name == "Stretch twice")
    #expect(!store.hasPendingAutosaveDraftForTermination)

    let renamed = try await stored(habit.id, in: core)
    store.noteHabitFieldDraft(HabitFieldDraft(habit: renamed, field: .cue, text: "  "))
    #expect(await store.flushPendingAutosaveDraftsForTermination())
    #expect(try await stored(habit.id, in: core).cue == nil)
  }

  @Test("text that changes nothing, or an emptied name, does not hold Quit")
  func unchangedTextDoesNotHoldQuit() async throws {
    let core = try await makeSeededInMemoryCore()
    let (store, habit) = try await makeStore(core)

    store.noteHabitFieldDraft(HabitFieldDraft(habit: habit, field: .name, text: " Stretch"))
    #expect(!store.hasPendingAutosaveDraftForTermination)
    store.noteHabitFieldDraft(HabitFieldDraft(habit: habit, field: .name, text: "   "))
    #expect(!store.hasPendingAutosaveDraftForTermination)
    store.noteHabitFieldDraft(HabitFieldDraft(habit: habit, field: .cue, text: "Loosen up"))
    #expect(!store.hasPendingAutosaveDraftForTermination)
  }

  @Test("Quit waits for a field's write that is still running")
  func quitWaitsForARunningWrite() async throws {
    let core = try await makeSeededInMemoryCore()
    let (store, habit) = try await makeStore(core)

    // Return, then ⌘Q before the write has run.
    store.commitHabitField(HabitFieldDraft(habit: habit, field: .cue, text: "One more"))
    #expect(store.hasPendingAutosaveDraftForTermination)
    #expect(await store.flushPendingAutosaveDraftsForTermination())
    #expect(try await stored(habit.id, in: core).cue == "One more")
  }

  @Test("a write that fails keeps the text and cancels Quit")
  func failedWriteCancelsQuit() async throws {
    let preview = try await makeSeededInMemoryCore()
    let habit = try await preview.createHabit(name: "Stretch", cue: "Loosen up", targetCount: 1)
    let core = StubCoreService(preview: preview)
    let store = AppStore(core: core)
    await store.refresh()
    core.updateHabitError = .validation(field: "name", message: "Too long.")

    let typed = HabitFieldDraft(habit: habit, field: .name, text: "Stretch at noon")
    store.noteHabitFieldDraft(typed)
    #expect(await store.flushPendingAutosaveDraftsForTermination() == false)
    #expect(store.habitFieldDraft == typed)
    #expect(try await stored(habit.id, in: preview).name == "Stretch")
  }
}
