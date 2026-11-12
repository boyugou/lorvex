import Foundation

/// Durable Watch command boundary implemented by the writable phone core.
public protocol LorvexWatchCommandServicing: Sendable {
  /// Canonical lowercase UUID for the currently open physical database.
  func currentWatchWorkspaceInstanceID() async throws -> String

  /// Applies or durably replays one command and always returns an identity-bound
  /// ACK. Malformed wire Data is rejected before this boundary.
  func applyWatchCommand(_ command: LorvexWatchCommand) async -> LorvexWatchCommandAck

  /// Records a rejection for a command whose action this build cannot read
  /// (``LorvexWatchCommand/identityOfUnreadableAction(in:)``) and returns its
  /// ACK, so the stream's later commands can be applied. The ledger's ordering
  /// and replay rules apply as for any command.
  func rejectWatchCommandWithUnreadableAction(
    _ identity: LorvexWatchCommandIdentity
  ) async -> LorvexWatchCommandAck
}
