import Foundation
import GRDB
import Synchronization

/// Releases the managed store's file locks for as long as the host process is
/// suspended.
///
/// iOS terminates a process with `0xdead10cc` when the system suspends it while
/// it holds a lock on a file in a shared App Group container. The Lorvex
/// database is such a file, and its connections take the write lock up front
/// (`BEGIN IMMEDIATE`) and wait out contention for up to five seconds, so an
/// ordinary write still in flight when the app is backgrounded is precisely the
/// case the system kills for.
///
/// ``suspend()`` tells every connection `LorvexStore` opened to stop acquiring
/// locks: database work then raises `SQLITE_ABORT` or `SQLITE_INTERRUPT` until
/// ``resume()``. The sync pipeline classifies both as transient and retries
/// them without charging any retry budget, so suspending costs a deferred write
/// rather than a lost one.
///
/// A host whose process the system can suspend must pair the two calls: post
/// ``suspend()`` as it leaves the foreground, and ``resume()`` before it next
/// touches the database — including at the start of a background-task handler,
/// which runs while the app is otherwise backgrounded. Hosts the system does
/// not suspend this way (macOS) need neither; the notifications are simply
/// never posted and every connection behaves as if this type did not exist.
///
/// Suspension is a flag on each open connection, not on the process. A
/// connection that was open when ``suspend()`` was posted stays suspended until
/// a ``resume()``, and a connection opened afterwards starts resumed. Work that
/// the system starts in a backgrounded process through a cached service — an
/// App Intent, a notification action — can therefore find its connection
/// suspended; ``withBackgroundAccess(_:)`` is how such work takes the store
/// back.
public enum DatabaseSuspension {
  /// Stop the managed store from acquiring new database locks. Idempotent.
  public static func suspend() {
    NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
  }

  /// Let the managed store acquire database locks again. Idempotent, and
  /// required before database work that follows a ``suspend()``.
  public static func resume() {
    NotificationCenter.default.post(name: Database.resumeNotification, object: nil)
  }

  /// How a host takes the store back for the length of a piece of background
  /// work and gives it up again afterwards.
  ///
  /// The iOS app owns what decides this — whether the process is in the
  /// background and how many pieces of work are using the store — so it supplies
  /// both calls and ``withBackgroundAccess(_:)`` makes them around work that
  /// other modules start. ``begin`` resumes the store before the work. ``end``
  /// runs after the work however it ended, and suspends the store again only
  /// when the app is still in the background and no other work is using it.
  public struct BackgroundAccess: Sendable {
    public let begin: @Sendable () async -> Void
    public let end: @Sendable () async -> Void

    public init(
      begin: @escaping @Sendable () async -> Void,
      end: @escaping @Sendable () async -> Void
    ) {
      self.begin = begin
      self.end = end
    }
  }

  private static let installedBackgroundAccess = Mutex<BackgroundAccess?>(nil)

  /// Test-only isolation hook: a value bound here takes the place of the
  /// installed access for the work running inside the binding, so a test can
  /// watch the bracket without touching the process-wide installation that
  /// concurrent tests share. Product code never binds it.
  @TaskLocal static var backgroundAccessOverride: BackgroundAccess?

  /// Installs the host's ``BackgroundAccess``, which
  /// ``withBackgroundAccess(_:)`` uses. The iOS app installs it once at launch.
  /// Without one the bracket runs its work unchanged, which is right for hosts
  /// that never suspend the store (macOS, extension processes). Passing `nil`
  /// removes it.
  public static func installBackgroundAccess(_ access: BackgroundAccess?) {
    installedBackgroundAccess.withLock { $0 = access }
  }

  /// Runs `body` with the store resumed for its duration, through the installed
  /// ``BackgroundAccess``, and returns or throws what `body` does.
  ///
  /// Wrap work that writes to the store and can start while the app is in the
  /// background. A write that reuses a connection suspended earlier fails with
  /// `SQLITE_ABORT`, so without the bracket a Shortcuts action or a task
  /// reminder's button could do nothing and report a failure. Brackets may
  /// nest; the store is suspended again only when the outermost one ends and
  /// the app is in the background.
  public static func withBackgroundAccess<Value>(
    _ body: () async throws -> Value
  ) async rethrows -> Value {
    let access = backgroundAccessOverride ?? installedBackgroundAccess.withLock { $0 }
    return try await withBackgroundAccess(access, body)
  }

  /// ``withBackgroundAccess(_:)`` through an explicit `access`; `nil` runs
  /// `body` unchanged.
  public static func withBackgroundAccess<Value>(
    _ access: BackgroundAccess?,
    _ body: () async throws -> Value
  ) async rethrows -> Value {
    guard let access else { return try await body() }
    await access.begin()
    do {
      let value = try await body()
      await access.end()
      return value
    } catch {
      await access.end()
      throw error
    }
  }
}
