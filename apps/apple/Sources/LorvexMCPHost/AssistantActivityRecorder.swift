import Foundation
import LorvexCore

/// Records which MCP client this host serves and when it last used Lorvex, for
/// the app's Settings list of connected assistants.
///
/// The client's identity arrives once, in the MCP `initialize` handshake. The
/// host records it then, and refreshes the last-active time on tool calls at
/// most once per ``refreshInterval``, so a helper that stays connected for days
/// still shows when it was last used without writing on every call.
///
/// Recording is best effort: a failed write is dropped and never fails the
/// handshake or a tool call. Call sites run these methods in their own task so
/// a busy database cannot delay the `initialize` response or a tool result.
actor AssistantActivityRecorder {
  /// The minimum time between two recordings triggered by tool calls.
  static let refreshInterval: TimeInterval = 10 * 60

  private let service: any LorvexCoreServicing
  private let now: @Sendable () -> Date
  private var client: (name: String, title: String?, version: String?)?
  private var lastRecordedAt: Date?

  init(service: any LorvexCoreServicing, now: @escaping @Sendable () -> Date = { Date() }) {
    self.service = service
    self.now = now
  }

  /// Remembers the client from the `initialize` handshake and records it.
  func clientDidInitialize(name: String, title: String?, version: String?) async {
    client = (name, title, version)
    await record(force: true)
  }

  /// Refreshes the last-active time when ``refreshInterval`` has passed since
  /// the previous recording. Does nothing before the handshake has named the
  /// client.
  func toolWasCalled() async {
    await record(force: false)
  }

  private func record(force: Bool) async {
    guard let client else { return }
    let current = now()
    if !force, let lastRecordedAt,
      current.timeIntervalSince(lastRecordedAt) < Self.refreshInterval
    {
      return
    }
    // Set before the write so a call that arrives during it does not record
    // a second time.
    lastRecordedAt = current
    try? await service.recordAssistantActivity(
      clientName: client.name, clientTitle: client.title, clientVersion: client.version)
  }
}
