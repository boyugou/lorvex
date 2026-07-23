import LorvexCore
import MCP

extension CoreBridgeClient {
  func loadSessionContext() async throws -> Value {
    Self.sessionContextValue(from: try await service.getSessionContext())
  }
}
