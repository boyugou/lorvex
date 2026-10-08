import LorvexCore

#if canImport(UIKit)
  import UIKit

  /// Runs work that needs the database from a handler the system may start
  /// while the app is backgrounded.
  ///
  /// The managed store is suspended whenever the app leaves the foreground, so
  /// that no database lock is held at the moment the system suspends the
  /// process and the app is not terminated with `0xdead10cc` (see
  /// `DatabaseSuspension`). A background handler therefore has to take the
  /// database back for the length of its work, and give it up again on the way
  /// out.
  ///
  /// The exit is conditional on purpose. A silent push delivered while the app
  /// is in the foreground runs through the very same handler, and suspending
  /// there would leave the database refusing locks for every write the user
  /// goes on to make. `UIApplication.applicationState` — not the handler's
  /// identity — is what says whether this process is on its way back to
  /// suspension.
  ///
  /// Background work can overlap (a silent push arriving while the sync flush
  /// that runs on leaving the app is still going), so users are counted: the
  /// database is suspended only when the last one leaves.
  ///
  /// Work that other modules start — an App Intent, a notification's Complete
  /// or Defer button — reaches this through ``access``, which the app installs
  /// at launch (`DatabaseSuspension/installBackgroundAccess(_:)`) and the
  /// notification handler passes explicitly.
  @MainActor
  enum BackgroundDatabaseWork {
    private static var activeUsers = 0

    /// ``begin()`` and ``end()`` as the calls
    /// `DatabaseSuspension.withBackgroundAccess` makes around such work.
    nonisolated static let access = DatabaseSuspension.BackgroundAccess(
      begin: { await BackgroundDatabaseWork.begin() },
      end: { await BackgroundDatabaseWork.end() })

    static func run<T>(_ body: () async throws -> T) async rethrows -> T {
      begin()
      defer { end() }
      return try await body()
    }

    /// Takes the database for background work. Balance every call with
    /// ``end()``.
    static func begin() {
      activeUsers += 1
      DatabaseSuspension.resume()
    }

    /// Gives the database up; the last user out suspends it while the app is
    /// in the background.
    static func end() {
      activeUsers = max(activeUsers - 1, 0)
      if activeUsers == 0, UIApplication.shared.applicationState == .background {
        DatabaseSuspension.suspend()
      }
    }
  }
#endif
