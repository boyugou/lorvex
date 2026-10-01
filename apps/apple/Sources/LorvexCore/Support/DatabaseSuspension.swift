import Foundation
import GRDB

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
}
