import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// Covers the macOS task-detail dependencies editor's store plumbing: the
/// `taskDetailDependencies` binding's parse/serialize round-trip and dirty
/// semantics, cycle-safe candidate filtering, graceful handling of a missing
/// dependency target, and the core's save-time cycle backstop.
@MainActor
private func makeDependencyEditorStore() async throws -> AppStore {
  let suiteName = "AppStoreDependencyEditorTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  return AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
}

/// Sets `task.dependsOn` while preserving its other fields, so a test can build a
/// dependency graph through the same update path the app uses.
private func setDependsOn(
  _ core: any LorvexCoreServicing, _ task: LorvexTask, _ deps: [LorvexTask.ID]
) async throws -> LorvexTask {
  try await core.updateTask(
    id: task.id,
    title: task.title,
    notes: task.notes,
    priority: task.priority,
    estimatedMinutes: task.estimatedMinutes,
    dueDate: task.dueDate,
    plannedDate: task.plannedDate,
    availableFrom: task.availableFrom,
    tags: task.tags,
    dependsOn: deps)
}

@MainActor
@Test
func dependencyBindingRoundTripsAndFlipsDirtyCheck() async throws {
  let store = try await makeDependencyEditorStore()
  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id
  store.syncSelectedTaskDraft()
  #expect(!store.selectedTaskDraftHasChanges)

  let core = store.core
  let a = try await core.createTask(title: "Dependency A", notes: "")
  let b = try await core.createTask(title: "Dependency B", notes: "")

  // Writing the ordered-ID binding serializes into the same draft text the save
  // path reads, and the dirty check flips.
  store.taskDetailDependencies = [a.id, b.id]
  #expect(store.parsedTaskDetailDependencies == [a.id, b.id])
  #expect(store.taskDetailDependsOnText == "\(a.id), \(b.id)")
  #expect(store.selectedTaskDraftHasChanges)

  await store.saveSelectedTaskDraft()
  #expect(Set(store.selectedTask?.dependsOn ?? []) == Set([a.id, b.id]))
  // A no-op edit right after save stays non-dirty (draft == stored).
  #expect(!store.selectedTaskDraftHasChanges)

  // Reorder is a lossless round-trip through the text projection.
  store.taskDetailDependencies = [b.id, a.id]
  #expect(store.parsedTaskDetailDependencies == [b.id, a.id])

  // Removing a dependency flips the dirty check again and persists.
  store.taskDetailDependencies.removeAll { $0 == a.id }
  #expect(store.parsedTaskDetailDependencies == [b.id])
  #expect(store.selectedTaskDraftHasChanges)
  await store.saveSelectedTaskDraft()
  #expect(store.selectedTask?.dependsOn == [b.id])
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func dependencyCycleExclusionsCoverTransitiveDependents() async throws {
  let store = try await makeDependencyEditorStore()
  await store.refresh()
  let core = store.core

  // Chain C -> B -> A (each arrow is "depends on"): B depends on A, C depends on B.
  let a = try await core.createTask(title: "Chain A", notes: "")
  let b = try await core.createTask(title: "Chain B", notes: "")
  let c = try await core.createTask(title: "Chain C", notes: "")
  _ = try await setDependsOn(core, b, [a.id])
  _ = try await setDependsOn(core, c, [b.id])

  // A's cycle exclusions are A plus everything that transitively depends on A
  // (B and C), because A depending on either would close a cycle.
  #expect(await store.dependencyCycleExclusions(for: a.id) == Set([a.id, b.id, c.id]))
  // B is blocked only by A; C depends on B, so B's exclusions are B and C.
  #expect(await store.dependencyCycleExclusions(for: b.id) == Set([b.id, c.id]))
  // Nothing depends on C, so only C itself is excluded (self-dependency).
  #expect(await store.dependencyCycleExclusions(for: c.id) == Set([c.id]))
}

@MainActor
@Test
func dependencyCandidatesExcludeSelfSelectedAndCycleTasks() async throws {
  let store = try await makeDependencyEditorStore()
  await store.refresh()
  let core = store.core

  let a = try await core.createTask(title: "Chain A", notes: "")
  let b = try await core.createTask(title: "Chain B", notes: "")
  let c = try await core.createTask(title: "Chain C", notes: "")
  _ = try await setDependsOn(core, b, [a.id])
  _ = try await setDependsOn(core, c, [b.id])
  let standalone = try await core.createTask(title: "Standalone task", notes: "")

  // Editing A: self + both transitive dependents are filtered out of the picker.
  let exclusionsForA = await store.dependencyCycleExclusions(for: a.id)
  let candidateIDs = Set(
    await store.dependencyCandidates(matching: "", excluding: exclusionsForA).map(\.id))
  #expect(!candidateIDs.contains(a.id))
  #expect(!candidateIDs.contains(b.id))
  #expect(!candidateIDs.contains(c.id))
  // A non-cycle task is a valid candidate for A.
  #expect(candidateIDs.contains(standalone.id))

  // A query still filters by title and honours the exclusions: every "Chain"
  // task is cycle-excluded for A, so the search yields nothing.
  #expect(
    (await store.dependencyCandidates(matching: "Chain", excluding: exclusionsForA)).isEmpty)

  // Already-selected exclusion is independent of cycles.
  let filtered = await store.dependencyCandidates(
    matching: "", excluding: [standalone.id])
  #expect(!filtered.map(\.id).contains(standalone.id))
}

@MainActor
@Test
func dependencyTasksResolvesMissingTargetGracefullyAndStaysRemovable() async throws {
  let store = try await makeDependencyEditorStore()
  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id
  store.syncSelectedTaskDraft()
  let core = store.core

  let real = try await core.createTask(title: "Resolvable dependency", notes: "")
  // A well-formed id with no backing task stands in for a target that was
  // deleted or archived after being saved as a dependency.
  let missing = "00000000-0000-0000-0000-000000000000"
  store.taskDetailDependencies = [real.id, missing]

  // Only the resolvable target comes back; the missing one is omitted (its row
  // renders as an "unavailable" placeholder) and nothing crashes.
  let resolved = await store.dependencyTasks(for: store.taskDetailDependencies)
  #expect(resolved.map(\.id) == [real.id])
  #expect(store.taskDetailDependencies.count == 2)

  // The unresolved dependency is still removable through the binding.
  store.taskDetailDependencies.removeAll { $0 == missing }
  #expect(store.taskDetailDependencies == [real.id])
}

@MainActor
@Test
func savingADependencyCycleIsRejectedByTheCoreBackstop() async throws {
  let store = try await makeDependencyEditorStore()
  await store.refresh()
  let core = store.core

  // Chain C -> B -> A.
  let a = try await core.createTask(title: "Backstop A", notes: "")
  let b = try await core.createTask(title: "Backstop B", notes: "")
  let c = try await core.createTask(title: "Backstop C", notes: "")
  _ = try await setDependsOn(core, b, [a.id])
  _ = try await setDependsOn(core, c, [b.id])

  // Load A into the inspector and try to make it depend on C, which would close
  // the cycle A -> C -> B -> A. The picker would filter C out, but a direct save
  // must still be rejected by the core's save-time validation.
  store.selectedTaskID = a.id
  await store.loadSelectedTaskDetail()
  store.syncSelectedTaskDraft(force: true)
  #expect(store.selectedTask?.id == a.id)

  store.taskDetailDependencies = [c.id]
  #expect(store.selectedTaskCanSave)
  await store.saveSelectedTaskDraft()

  // The core rejects the cycle: the error surfaces and A's edges are unchanged.
  #expect(store.errorMessage != nil)
  #expect(try await core.loadTask(id: a.id).dependsOn.isEmpty)
}
