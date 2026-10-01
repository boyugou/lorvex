import Foundation
import LorvexCore
import Testing

@testable import LorvexMCPHost

/// The helper records its client at the `initialize` handshake and refreshes
/// the last-active time on tool calls at most once per refresh interval.
@Suite("Assistant activity recorder")
struct AssistantActivityRecorderTests {
  private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }

    func now() -> Date { lock.withLock { value } }
    func advance(by seconds: TimeInterval) { lock.withLock { value += seconds } }
  }

  private static let start = Date(timeIntervalSince1970: 1_790_000_000)

  @Test("a tool call before the handshake records nothing")
  func nothingBeforeHandshake() async throws {
    let clock = Clock(Self.start)
    let service = try SwiftLorvexCoreService.inMemory(wallClock: { clock.now() })
    let recorder = AssistantActivityRecorder(service: service, now: { clock.now() })

    await recorder.toolWasCalled()

    #expect(try await service.loadAssistantSessions().isEmpty)
  }

  @Test("the handshake records at once and tool calls refresh after the interval")
  func throttlesToolCallRefreshes() async throws {
    let clock = Clock(Self.start)
    let service = try SwiftLorvexCoreService.inMemory(wallClock: { clock.now() })
    let recorder = AssistantActivityRecorder(service: service, now: { clock.now() })
    let interval = AssistantActivityRecorder.refreshInterval

    await recorder.clientDidInitialize(name: "claude-code", title: "Claude Code", version: "2.1.0")
    #expect(try await service.loadAssistantSessions().map(\.lastActiveAt) == [Self.start])

    clock.advance(by: interval - 1)
    await recorder.toolWasCalled()
    #expect(try await service.loadAssistantSessions().map(\.lastActiveAt) == [Self.start])

    clock.advance(by: 1)
    await recorder.toolWasCalled()
    #expect(
      try await service.loadAssistantSessions().map(\.lastActiveAt) == [Self.start + interval])
  }
}
