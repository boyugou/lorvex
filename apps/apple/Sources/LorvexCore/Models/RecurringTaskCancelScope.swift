import Foundation

/// The scope a user picks when cancelling a *recurring* task, mirroring
/// Calendar.app's "This event / All events" prompt.
///
/// Each case maps to an ordered list of existing `LorvexTaskServicing`
/// operations that, run in sequence, realize the chosen scope. The mapping is
/// pure (`coreOperations`) so it can be unit-tested independently of the store;
/// the call sites just dispatch the returned operations through the service.
///
/// `thisAndFollowing` is intentionally absent: the core exposes no single
/// operation that drops the current occurrence *and* truncates the remaining
/// tail, and composing one would fabricate per-occurrence semantics the core
/// does not have (the recurrence-exception primitive only pre-skips a *future*
/// occurrence — it never removes the instance currently due).
public enum RecurringTaskCancelScope: String, Sendable, CaseIterable {
  /// Cancel only the occurrence the user is looking at; the series continues.
  case thisOccurrence
  /// Cancel this occurrence and end the whole series (no future occurrences).
  case all

  /// A single existing `LorvexTaskServicing` operation in the sequence that
  /// realizes a cancel scope.
  public enum Operation: Equatable, Sendable {
    /// `removeTaskRecurrence(taskID:)` — drop the recurrence rule so no
    /// successor can spawn.
    case removeRecurrence
    /// `cancelTask(id:)` — the dedicated cancel op (cancels this occurrence;
    /// for a still-recurring task it spawns the next occurrence).
    case cancelTask
  }

  /// The ordered core operations that realize this scope.
  ///
  /// - `.thisOccurrence` → `[.cancelTask]`. `cancelTask` cancels the current
  ///   occurrence and spawns the next one, leaving the series intact.
  /// - `.all` → `[.removeRecurrence, .cancelTask]`. Order is load-bearing:
  ///   removing the rule first means the subsequent `cancelTask` sees no
  ///   recurrence and spawns no successor, so the series ends. Cancelling
  ///   first would spawn a successor that the later rule-removal could not
  ///   reach.
  public var coreOperations: [Operation] {
    switch self {
    case .thisOccurrence: [.cancelTask]
    case .all: [.removeRecurrence, .cancelTask]
    }
  }
}
