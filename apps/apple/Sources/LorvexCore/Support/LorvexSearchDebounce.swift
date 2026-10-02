import Foundation

/// The typing pause a search field waits out before it queries. A typed query
/// runs once the person has stopped typing for ``pause``; an empty query, such
/// as a cleared field or the initial list, runs at once.
///
/// A search runs in a `.task(id:)` keyed by its query, which SwiftUI cancels,
/// without awaiting it, as soon as the query changes. A caller therefore checks
/// `Task.isCancelled` again once its own query returns and drops a cancelled
/// result, so a slower reply to a superseded query never replaces the newer
/// query's results, and leaves its loading state to the run that replaced it.
public enum LorvexSearchDebounce {
  /// How long typing must pause before a typed query runs.
  public static let pause: Duration = .milliseconds(250)

  /// Waits out the typing pause for `query`, then reports whether its search
  /// should still run: false once the surrounding task has been cancelled,
  /// because a newer query superseded this one.
  public static func shouldSearch(_ query: String) async -> Bool {
    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      try? await Task.sleep(for: pause)
    }
    return !Task.isCancelled
  }
}
