import Foundation
import GRDB
import LorvexStore
import Testing

@testable import LorvexCore

/// The MCP helper records which assistants use Lorvex so Settings can list
/// them. The record is device-local bookkeeping: it must reach neither the sync
/// wire nor the assistant change log.
@Suite("Assistant sessions")
struct AssistantSessionsServiceTests {
  @Test("a recorded client reads back stamped with the service clock")
  func roundTrip() async throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-28T17:04:05Z"))
    let service = try SwiftLorvexCoreService.inMemory(wallClock: { now })

    try await service.recordAssistantActivity(
      clientName: "claude-code", clientTitle: "Claude Code", clientVersion: "2.1.0")

    #expect(
      try await service.loadAssistantSessions() == [
        AssistantSessionRecord(
          clientName: "claude-code", clientTitle: "Claude Code", clientVersion: "2.1.0",
          lastActiveAt: now)
      ])
  }

  @Test("recording writes no outbox row, change-log entry, or device identity")
  func staysLocal() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let before = try Self.syncFootprint(service)

    try await service.recordAssistantActivity(
      clientName: "claude-ai", clientTitle: nil, clientVersion: "0.14.2")

    #expect(try Self.syncFootprint(service) == before)
    #expect(try await service.loadAssistantSessions().map(\.clientName) == ["claude-ai"])
  }

  @Test("known clients show their product name, others their title or identifier")
  func displayNames() {
    func record(_ name: String, title: String?) -> AssistantSessionRecord {
      AssistantSessionRecord(
        clientName: name, clientTitle: title, clientVersion: nil, lastActiveAt: .distantPast)
    }
    #expect(record("claude-ai", title: "Claude").displayName == "Claude Desktop")
    #expect(record("claude-code", title: nil).displayName == "Claude Code")
    #expect(record("zed", title: "Zed").displayName == "Zed")
    #expect(record("my-agent", title: nil).displayName == "my-agent")
  }

  private static func syncFootprint(_ service: SwiftLorvexCoreService) throws -> [String] {
    try service.read { db in
      [
        String(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox") ?? -1),
        String(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? -1),
        try SyncCheckpoints.get(db, key: SyncCheckpoints.keyDeviceId) ?? "no device id",
      ]
    }
  }
}
