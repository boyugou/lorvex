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
  /// While any work holds the database, so does a UIKit background task. Some
  /// of that work has no system window of its own (a Watch message, the Watch
  /// session's activation refresh, an App Intent's tail), and without a task
  /// the system suspends the process whenever the window it was woken for
  /// closes, which may be mid-transaction. If the task's time runs out first,
  /// its expiration suspends the database before the system suspends the
  /// process: work still running then fails with the transient suspended error
  /// rather than holding a lock across suspension.
  ///
  /// Work that other modules start — an App Intent, a notification's Complete
  /// or Defer button — reaches this through ``access``, which the app installs
  /// at launch (`DatabaseSuspension/installBackgroundAccess(_:)`) and the
  /// notification handler passes explicitly.
  @MainActor
  enum BackgroundDatabaseWork {
    private static var activeUsers = 0
    private static var backgroundTask: UIBackgroundTaskIdentifier = .invalid

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
      if backgroundTask == .invalid {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Lorvex database") {
          expire()
        }
      }
    }

    /// Gives the database up; the last user out suspends it while the app is
    /// in the background, and ends the background task.
    static func end() {
      activeUsers = max(activeUsers - 1, 0)
      guard activeUsers == 0 else { return }
      if UIApplication.shared.applicationState == .background {
        DatabaseSuspension.suspend()
      }
      endBackgroundTask()
    }

    /// The background task's time ran out with work still holding the
    /// database: release every lock before the system suspends the process.
    /// The users still counted end later; the last one finds nothing to end.
    private static func expire() {
      DatabaseSuspension.suspend()
      endBackgroundTask()
    }

    private static func endBackgroundTask() {
      guard backgroundTask != .invalid else { return }
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }
#endif
