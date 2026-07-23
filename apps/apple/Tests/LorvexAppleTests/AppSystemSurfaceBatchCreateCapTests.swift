import Foundation
import LorvexCore
import Testing

/// The batch-create App Intent runs its whole payload in one write transaction,
/// so it must reject a set above the shared `LorvexBatchLimits.maxItems` cap the
/// MCP batch tools enforce — otherwise a large Shortcuts/Siri payload could hold
/// the write lock long enough to starve sync/UI writes.
@Test
func batchCreateTasksAtCapSucceedsAndAboveCapThrows() async throws {
  let core = try await makeSeededInMemoryCore()

  let atCap = (1...LorvexBatchLimits.maxItems)
    .map { "Cap task \($0)" }
    .joined(separator: ",")
  let created = try await LorvexSystemIntentRunner.batchCreateTasks(
    titlesText: atCap, notes: nil, listID: nil, priority: nil, core: core)
  #expect(created.count == LorvexBatchLimits.maxItems)

  let aboveCap = (1...(LorvexBatchLimits.maxItems + 1))
    .map { "Over task \($0)" }
    .joined(separator: ",")
  await #expect(throws: (any Error).self) {
    _ = try await LorvexSystemIntentRunner.batchCreateTasks(
      titlesText: aboveCap, notes: nil, listID: nil, priority: nil, core: core)
  }
}
