import LorvexCore

/// A real `SwiftLorvexCoreService` over an empty in-memory GRDB store running
/// the canonical schema. The default core for app-layer tests: production
/// query/write semantics with no on-disk footprint and no cross-test state.
func makeInMemoryCore() throws -> SwiftLorvexCoreService {
  try SwiftLorvexCoreService.inMemory()
}

/// A real in-memory core pre-populated with the fixed preview dataset
/// (`LorvexPreviewCoreFactory.makeSeeded`): the lists/tasks/habits/calendar/
/// memory/review fixture tests reference through `LorvexPreviewSeedID`.
func makeSeededInMemoryCore() async throws -> SwiftLorvexCoreService {
  try await LorvexPreviewCoreFactory.makeSeeded()
}
