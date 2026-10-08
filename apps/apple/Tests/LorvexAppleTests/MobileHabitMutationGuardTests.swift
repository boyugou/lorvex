import Foundation
import LorvexCore
import LorvexMobile
import Testing

/// A habit tap writes and shows its result at once; the widget snapshot and the
/// reminder plan follow it. These tests hold that follow-up open and check that
/// the next tap, the feedback, and the failure path do not wait for it.

@MainActor
private final class ReturnCounter {
  var count = 0
}

/// Polls the main actor until `condition` holds, for state that settles on a
/// later turn than the call that started it. Returns as soon as the condition
/// holds; the ceiling is generous because a full test run queues many tests on
/// the main actor and each poll waits its turn. False on timeout.
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
private func completionsToday(_ id: LorvexHabit.ID, in store: MobileStore) -> Int? {
  store.habits?.habits.first { $0.id == id }?.completionsToday
}

@MainActor
@Test
func mobileStoreWritesASecondHabitWhileTheFirstOnesSurfacesArePublishing() async throws {
  let core = try await makeSeededInMemoryCore()
  let stretch = try await core.createHabit(name: "Stretch", cue: nil, targetCount: 1)
  let read = try await core.createHabit(name: "Read", cue: nil, targetCount: 1)
  let gate = GatedMobileWidgetSnapshotPublisher()
  let store = MobileStore(
    core: core, widgetSnapshotPublisher: gate, todayString: { "2026-05-23" })
  await store.refresh()
  let first = try #require(store.habits?.habits.first { $0.id == stretch.id })
  let second = try #require(store.habits?.habits.first { $0.id == read.id })
  #expect(completionsToday(second.id, in: store) == 0)

  gate.holdNextPublication()
  let firstTap = Task { await store.completeHabit(first) }
  #expect(await settle { gate.isHolding }, "the first tap reached its widget publication")

  let returns = ReturnCounter()
  let secondTap = Task {
    let completed = await store.completeHabit(second)
    returns.count += 1
    return completed
  }
  _ = await settle { completionsToday(second.id, in: store) == 1 || returns.count == 1 }

  #expect(completionsToday(second.id, in: store) == 1, "the second tap is written, not dropped")
  #expect(completionsToday(first.id, in: store) == 1)
  #expect(store.isMutatingHabit == false)

  gate.release()
  #expect(await firstTap.value)
  #expect(await secondTap.value)
}

@MainActor
@Test
func mobileStoreCountsEveryTapOnAMultiCountHabitWhileSurfacesPublish() async throws {
  let core = try await makeSeededInMemoryCore()
  let water = try await core.createHabit(name: "Water", cue: nil, targetCount: 5)
  let gate = GatedMobileWidgetSnapshotPublisher()
  let store = MobileStore(
    core: core, widgetSnapshotPublisher: gate, todayString: { "2026-05-23" })
  await store.refresh()
  let habit = try #require(store.habits?.habits.first { $0.id == water.id })
  let publicationsBefore = gate.publicationCount

  gate.holdNextPublication()
  var taps = [Task { await store.completeHabit(habit) }]
  #expect(await settle { gate.isHolding }, "the first tap reached its widget publication")

  // Each later tap starts after the previous write has landed, as separate
  // taps of one finger do.
  let returns = ReturnCounter()
  for expectedCount in 2...3 {
    taps.append(
      Task {
        let completed = await store.completeHabit(habit)
        returns.count += 1
        return completed
      })
    _ = await settle {
      completionsToday(habit.id, in: store) == expectedCount || returns.count == expectedCount - 1
    }
  }

  #expect(completionsToday(habit.id, in: store) == 3, "each tap counts")

  gate.release()
  for tap in taps { #expect(await tap.value) }
  // The taps that arrived while a pass was publishing share one trailing pass.
  #expect(gate.publicationCount - publicationsBefore == 2)
  #expect(store.isMutatingHabit == false)
}

@MainActor
@Test
func mobileStorePlaysHabitFeedbackBeforeItsSurfacesFinish() async throws {
  let core = try await makeSeededInMemoryCore()
  let gate = GatedMobileWidgetSnapshotPublisher()
  let feedback = RecordingFeedbackProvider()
  let store = MobileStore(
    core: core, feedbackProvider: feedback, widgetSnapshotPublisher: gate,
    todayString: { "2026-05-23" })
  await store.refresh()
  let habit = try #require(
    store.habits?.habits.first { $0.id == LorvexPreviewSeedID.eveningWalkHabit })

  gate.holdNextPublication()
  let tap = Task { await store.completeHabit(habit) }
  #expect(await settle { gate.isHolding }, "the tap reached its widget publication")

  #expect(
    feedback.recorded.contains(.habitCompleted), "the feedback does not wait for the widget")

  gate.release()
  #expect(await tap.value)
}

@MainActor
@Test
func mobileStoreReleasesTheHabitGuardWhenTheWriteFails() async throws {
  // The stub core rejects habit completion, which stands for a write that fails.
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let feedback = RecordingFeedbackProvider()
  let store = MobileStore(
    core: core, feedbackProvider: feedback, todayString: { "2026-05-23" })
  await store.refresh()
  let habit = try #require(store.habits?.habits.first)

  let completed = await store.completeHabit(habit)

  #expect(completed == false)
  #expect(store.errorMessage != nil)
  #expect(store.isMutatingHabit == false)
  #expect(feedback.recorded.isEmpty)
}
