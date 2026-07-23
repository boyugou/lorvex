import Foundation
import LorvexCore

/// A rejected watch command retained in the durable journal until the user
/// explicitly dismisses it. Rejections are terminal for FIFO delivery, but are
/// not silently erased: the watch keeps enough context to explain that an
/// optimistic action did not apply on the phone.
public struct LorvexWatchRejectedCommand: Identifiable, Equatable, Sendable {
  public let id: String
  public let sequence: Int64
  public let mutation: LorvexWatchMutation
  public let code: String
  public let reason: String

  public init(
    id: String,
    sequence: Int64,
    mutation: LorvexWatchMutation,
    code: String,
    reason: String
  ) {
    self.id = id
    self.sequence = sequence
    self.mutation = mutation
    self.code = code
    self.reason = reason
  }
}

/// Converts stable phone protocol codes into Watch-owned localized copy. Phone
/// diagnostic messages are intentionally not surfaced: they are English wire
/// diagnostics, not user-facing localized content.
enum LorvexWatchDeliveryRejectionText {
  static let workspaceReplacedCode = "workspace_replaced"

  static func localizedMessage(for code: String) -> String {
    switch code {
    case workspaceReplacedCode:
      return String(
        localized: "watch.delivery.workspace_replaced",
        defaultValue: "The iPhone workspace was replaced before this action was applied.",
        table: "Localizable", bundle: WatchL10n.bundle)
    case "not_found":
      return String(
        localized: "watch.delivery.rejection.not_found",
        defaultValue: "The item no longer exists on iPhone.",
        table: "Localizable", bundle: WatchL10n.bundle)
    case "invalid_title":
      return String(
        localized: "watch.delivery.rejection.invalid_title",
        defaultValue: "The task title is no longer valid.",
        table: "Localizable", bundle: WatchL10n.bundle)
    case "validation_failed":
      return String(
        localized: "watch.delivery.rejection.validation_failed",
        defaultValue: "This action is no longer valid.",
        table: "Localizable", bundle: WatchL10n.bundle)
    case "conflict":
      return String(
        localized: "watch.delivery.rejection.conflict",
        defaultValue: "This action conflicts with newer changes.",
        table: "Localizable", bundle: WatchL10n.bundle)
    case "command_id_collision", "sequence_reuse":
      return String(
        localized: "watch.delivery.rejection.out_of_date",
        defaultValue: "This saved action is out of date.",
        table: "Localizable", bundle: WatchL10n.bundle)
    default:
      return String(
        localized: "watch.delivery.rejection.generic",
        defaultValue: "This action wasn't applied on iPhone.",
        table: "Localizable", bundle: WatchL10n.bundle)
    }
  }
}

/// A durably queued command awaiting an application acknowledgement.
public struct LorvexWatchPendingCommand: Identifiable, Equatable, Sendable {
  public let id: String
  public let sequence: Int64
  public let mutation: LorvexWatchMutation

  public init(id: String, sequence: Int64, mutation: LorvexWatchMutation) {
    self.id = id
    self.sequence = sequence
    self.mutation = mutation
  }
}

/// User-visible summary of the watch command journal.
public struct LorvexWatchDeliveryStatus: Equatable, Sendable {
  public let pendingCommands: [LorvexWatchPendingCommand]
  public let rejectedCommands: [LorvexWatchRejectedCommand]
  public let journalUnavailable: Bool

  public init(
    pendingCommands: [LorvexWatchPendingCommand] = [],
    rejectedCommands: [LorvexWatchRejectedCommand] = [],
    journalUnavailable: Bool = false
  ) {
    self.pendingCommands = pendingCommands
    self.rejectedCommands = rejectedCommands
    self.journalUnavailable = journalUnavailable
  }

  public var pendingCount: Int { pendingCommands.count }

  public static let empty = LorvexWatchDeliveryStatus()
}

/// Watch-owned controls layered on top of the platform-neutral forwarding
/// protocol. The store keeps accepting the small Core protocol for test doubles;
/// production conditionally adopts this richer surface to observe and manage the
/// durable journal.
public protocol LorvexWatchDeliveryManaging: LorvexWatchMutationForwarding {
  func setDeliveryStatusHandler(
    _ handler: @escaping @Sendable (LorvexWatchDeliveryStatus) -> Void
  )
  func dismissRejectedCommand(id: String) async
  func drain() async
  func handleBackgroundWake() async
}

/// Connectivity state consumed by the pure delivery coordinator. An inactive
/// session is intentionally distinct from an activated but unreachable session:
/// only the latter may enqueue a background `transferUserInfo`.
enum LorvexWatchDeliveryChannelState: Equatable, Sendable {
  case inactive
  case reachable
  case background
}

/// Deterministic retry policy shared by direct-send failures, retryable phone
/// acknowledgements, and completed background transfers that have not yet
/// received an application acknowledgement.
struct LorvexWatchDeliveryRetryPolicy: Equatable, Sendable {
  let initialDelay: TimeInterval
  let maximumDelay: TimeInterval
  let acknowledgementTimeout: TimeInterval

  init(
    initialDelay: TimeInterval = 5,
    maximumDelay: TimeInterval = 5 * 60,
    acknowledgementTimeout: TimeInterval = 30
  ) {
    self.initialDelay = initialDelay
    self.maximumDelay = maximumDelay
    self.acknowledgementTimeout = acknowledgementTimeout
  }

  func retryDelay(afterAttempt attempt: Int) -> TimeInterval {
    guard attempt > 0 else { return initialDelay }
    let exponent = min(attempt - 1, 16)
    return min(initialDelay * pow(2, Double(exponent)), maximumDelay)
  }
}
