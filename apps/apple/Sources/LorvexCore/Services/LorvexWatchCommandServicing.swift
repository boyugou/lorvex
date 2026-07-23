import Foundation

/// Durable Watch command boundary implemented by the writable phone core.
public protocol LorvexWatchCommandServicing: Sendable {
  /// Canonical lowercase UUID for the currently open physical database.
  func currentWatchWorkspaceInstanceID() async throws -> String

  /// Applies or durably replays one command and always returns an identity-bound
  /// ACK. Malformed wire Data is rejected before this boundary.
  func applyWatchCommand(_ command: LorvexWatchCommand) async -> LorvexWatchCommandAck
}
