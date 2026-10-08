import LorvexCore
import LorvexMobile

#if canImport(UIKit)
  import UIKit

  /// Finishes the app's save and sync work as it leaves the foreground, then
  /// suspends the database.
  ///
  /// The managed store must give up its locks before iOS suspends the process:
  /// holding one across suspension is what iOS terminates as `0xdead10cc`
  /// (see `DatabaseSuspension`). Suspending at once, though, would leave an
  /// edit made just before leaving the app queued until the next launch, and
  /// would lose a daily review entry still being typed. So the flush first
  /// writes the drafts that save on their own, then runs one sync pass inside a
  /// background task, and suspends the database when that pass ends or the
  /// task's time runs out, whichever comes first. Other background work still
  /// using the database at that point keeps it open until it ends too.
  /// Returning to the foreground before then resumes the database as usual, and
  /// the late suspension is skipped because the app is no longer in the
  /// background.
  @MainActor
  enum BackgroundSyncFlush {
    static func flushThenSuspend(store: MobileStore) {
      BackgroundDatabaseWork.begin()
      let flush = Flush()
      flush.taskID = UIApplication.shared.beginBackgroundTask(withName: "Lorvex sync") {
        flush.finish()
      }
      guard flush.taskID != .invalid else {
        flush.finish()
        return
      }
      Task {
        await store.flushAutosaveDraftsBeforeSuspension()
        await store.flushCloudSyncBeforeSuspension()
        flush.finish()
      }
    }

    /// One flush's background task; `finish()` runs its exit once.
    @MainActor
    private final class Flush {
      var taskID: UIBackgroundTaskIdentifier = .invalid
      private var finished = false

      func finish() {
        guard !finished else { return }
        finished = true
        BackgroundDatabaseWork.end()
        if taskID != .invalid {
          UIApplication.shared.endBackgroundTask(taskID)
        }
      }
    }
  }
#endif
