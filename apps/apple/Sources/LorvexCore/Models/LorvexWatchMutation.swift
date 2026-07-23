import Foundation

// The watch↔phone mutation envelope + forwarding protocol. Platform-neutral and
// WatchConnectivity-free, so it lives in LorvexCore where BOTH the phone
// (LorvexMobile) and the watch (LorvexWatch) can use it without a cross-platform
// target dependency. The concrete WCSession forwarder stays in LorvexWatch.

// MARK: - WatchConnectivity payload keys

/// Payload keys exchanged between the iPhone and the watch. Commands and ACKs
/// can travel through direct messages or background user info; the latest-state
/// replica travels through application context. Platform-neutral so both sides
/// share exact keys without importing WatchConnectivity in Core.
public enum LorvexWatchConnectivityKey {
  /// Strict V1 ``LorvexWatchCommand`` Data sent Watch→phone.
  public static let commandEnvelopeV1 = "lorvex.watchCommand.v1"
  /// Strict V1 ``LorvexWatchCommandAck`` Data sent phone→Watch.
  public static let commandAckV1 = "lorvex.watchCommandAck.v1"
  /// Strict V1 ``LorvexWatchReplicaEnvelope`` Data sent phone→Watch.
  public static let replicaEnvelopeV1 = "lorvex.watchReplicaEnvelope.v1"
}

// MARK: - Errors

/// An error returned by the phone when it applies a forwarded mutation.
public enum WatchForwardingError: LocalizedError, Sendable {
  /// The watch connectivity session cannot currently accept outgoing mutations.
  case unavailable

  public var errorDescription: String? {
    switch self {
    case .unavailable:
      return "Watch connectivity is not ready. Open Lorvex on iPhone and try again."
    }
  }
}

// MARK: - Mutation enum

/// A watch-originated mutation that the phone applies through its writable core.
///
/// Each case maps 1:1 to a `LorvexCoreServicing` method or a MobileStore wrapper.
public enum LorvexWatchMutation: Codable, Sendable, Equatable {
  case completeTask(id: LorvexTask.ID)
  case cancelTask(id: LorvexTask.ID)
  case deferTaskToTomorrow(id: LorvexTask.ID, plannedDate: String)
  case removeFromFocus(id: LorvexTask.ID, date: String)
  case captureTask(title: String)
  case completeHabit(id: LorvexHabit.ID, date: String)
}

// MARK: - Forwarding protocol

/// Forwards watch-originated mutations to the phone for application.
///
/// Implementations must be safe to call from `@MainActor` contexts. Concrete
/// implementations are gated behind `#if canImport(WatchConnectivity)`.
public protocol LorvexWatchMutationForwarding: Sendable {
  func forward(_ mutation: LorvexWatchMutation) async throws
}
