import LorvexRuntime
import LorvexStore
import MCP
import Testing

@testable import LorvexCore
@testable import LorvexMCPHost

@Suite("MCP Tool Registry — system area")
struct SystemToolTests {

  @Test("get_session_context returns the flat production session-context shape")
  func sessionContext() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(registry, tool: "get_session_context")
    #expect(result.isError != true)
    #expect(!mcpTextContent(result).isEmpty)
    // Flat envelope matching the on-disk core adapter.
    let object = try #require(result.structuredContent?.objectValue)
    #expect(object["date"]?.stringValue != nil)
    #expect(object["weekday"]?.stringValue != nil)
    #expect(object["local_time"]?.stringValue?.wholeMatch(of: #/\d{2}:\d{2}/#) != nil)
    #expect(object["sync_backend"]?.stringValue == "unknown")
    #expect(object.keys.contains("device_id"))
    #expect(object.keys.contains("timezone"))
    #expect(object.keys.contains("working_hours"))
  }

  @Test("get_overview compact top_tasks are the slim projection, not full tasks")
  func overviewCompact() async throws {
    let registry = try mcpInMemoryRegistry()
    _ = try await mcpRegistryCall(
      registry, tool: "create_task", arguments: ["title": .string("Top task fixture")])
    let result = try await mcpRegistryCall(registry, tool: "get_overview")
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["stats"] != nil)
    let top = try #require(
      result.structuredContent?.objectValue?["top_tasks"]?.arrayValue?.first?.objectValue)
    // Shared slim summary keys.
    for key in ["id", "title", "status", "list_id", "priority", "due_date", "planned_date"] {
      #expect(top.keys.contains(key), "missing \(key)")
    }
    // The heavy full-task fields must not leak into the compact projection.
    for heavy in ["notes", "priority_label", "checklist_items", "reminders", "tags"] {
      #expect(top[heavy] == nil, "unexpected full-task field \(heavy)")
    }
  }

  @Test("get_overview full shape returns non-error result")
  func overview() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(
      registry, tool: "get_overview", arguments: ["shape": .string("full")])
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["tasks"] != nil)
  }

  @Test("get_overview surfaces overview read failures")
  func overviewSurfacesReadFailure() async throws {
    let core = StubCoreService(preview: try await makeSeededInMemoryCore())
    core.loadOverviewTaskListError = .unsupportedOperation("Overview unavailable.")
    let bridge = CoreBridgeClient(databasePath: "/tmp/lorvex-test.sqlite", service: core)
    let registry = ToolRegistry(coreBridge: bridge)

    // The downstream read failure is surfaced as a clean structured tool error
    // through the dispatch error boundary rather than thrown to the transport.
    let result = try await mcpRegistryCall(
      registry, tool: "get_overview", arguments: ["shape": .string("full")])
    #expect(result.isError == true)
    #expect(mcpTextContent(result).contains("Overview unavailable."))
  }

  @Test("get_all_preferences returns non-error result")
  func getAllPreferences() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await mcpRegistryCall(registry, tool: "get_all_preferences")
    #expect(result.isError != true)
  }

  @Test("get_sync_status surfaces reseed_required and reports sync_backend_kind unknown")
  func syncStatusReseedRequiredAndBackendUnknown() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    try service.write { db in
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyReseedRequired, value: "true")
    }

    let result = try await mcpRegistryCall(registry, tool: "get_sync_status")
    #expect(result.isError != true)
    let object = try #require(result.structuredContent?.objectValue)
    // The durable recovery marker the core loads is now surfaced to the MCP client.
    #expect(object["reseed_required"]?.boolValue == true)
    // This process can't observe the live CloudKit transport, so the backend
    // kind is the honest placeholder rather than an asserted mode.
    #expect(object["sync_backend_kind"]?.stringValue == "unknown")
  }
}
