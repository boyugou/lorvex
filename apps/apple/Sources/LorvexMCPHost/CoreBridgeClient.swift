import Foundation
import LorvexDomain
import LorvexCore

/// MCP-host backend over the pure-Swift `SwiftLorvexCoreService`.
///
/// Holds a `LorvexCoreServicing` and delegates every operation to the matching
/// service method, mapping the service's `LorvexCore` model results onto the MCP
/// `Value` JSON shapes the tool handlers return. The model→`Value` mapping lives
/// in the `CoreBridgeClient*ValueAdapters` extensions; the JSON field names and
/// shapes match the contract external MCP clients depend on.
///
/// Operations whose service method throws `LorvexCoreError.unsupportedOperation`
/// keep their delegation: the throw surfaces to the caller as an MCP error.
struct CoreBridgeClient: Sendable {
  let service: any LorvexCoreServicing

  init(databasePath: String?) {
    // No `writeInitiatorDefault` override: the MCP host keeps the fail-closed
    // `.unattributed` default and binds `.assistant` for the duration of each
    // tool call in `ToolRegistry.call`, so a new MCP write path that bypasses
    // that dispatch binding records `.unattributed` (caught) rather than a
    // silent human `.user`.
    self.service = SwiftLorvexCoreService(databasePath: databasePath, surface: .mcp)
  }

  /// Test seam: inject an arbitrary service (e.g. an in-memory-backed
  /// `SwiftLorvexCoreService`).
  init(databasePath: String?, service: any LorvexCoreServicing) {
    self.service = service
  }

  /// Returns the durable idempotency backend if the underlying service
  /// supports it. `SwiftLorvexCoreService` does (on-disk and in-memory alike);
  /// only an injected stub service without the conformance yields `nil`.
  var mcpIdempotency: (any LorvexMcpIdempotencyServicing)? {
    service as? any LorvexMcpIdempotencyServicing
  }

  /// Rich-return mutation surface implemented by the production Swift core.
  /// Keeping the cast explicit makes injected test doubles fail closed instead
  /// of silently falling back to a read-before/write or write/read sequence.
  var mcpMutations: any LorvexMcpMutationServicing {
    get throws {
      guard let mutations = service as? any LorvexMcpMutationServicing else {
        throw LorvexCoreError.unsupportedOperation(
          "This backend does not support atomic MCP mutation receipts.")
      }
      return mutations
    }
  }
}
