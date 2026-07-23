import Foundation
import GRDB

/// In-process memoization of the completion-streak walk.
///
/// `Overview.queryCompletionStreak` folds up to ~365 days of completion
/// timestamps on every call. The result is a pure function of three inputs:
/// the connection's `local_change_seq` (bumped inside every `withWrite`, so any
/// task mutation moves it), the local `today` YMD, and the active timezone
/// name. This cache stores the last computed streak per connection and returns
/// it when all three key components are unchanged, eliminating the re-walk on
/// the dominant no-intervening-write read path.
///
/// **Scope — single process.** The cache is a process-global keyed weakly on
/// the `Database` object itself (a `NSMapTable.weakToStrongObjects`). A GRDB
/// `DatabaseQueue`/`DatabasePool` reuses the same `Database` object across
/// reads, so the slot is stable for a store's lifetime; when the store (and its
/// connection) deallocates, the weak key drops the slot. This avoids the
/// `ObjectIdentifier` hazard where a later `Database` allocated at a freed
/// address would inherit a defunct slot — distinct connections never share a
/// slot, even sequentially. Other processes that open the same file (e.g. the
/// widget) hold their own `Database` objects and so recompute independently —
/// acceptable because the app process is the dominant reader and the streak is
/// cheap to recompute cold.
///
/// **Invalidation.** Keyed on `local_change_seq`, which the writer bumps in
/// every mutating transaction. A write between two reads advances the seq, so
/// the second read misses the cache and recomputes. `local_change_seq` is a
/// coarse signal — it moves on writes unrelated to completions too — so the
/// cache over-invalidates (recomputes more than strictly necessary) but never
/// returns a stale streak. `today`/`timezone` are part of the key so a day
/// rollover or timezone change also recomputes.
final class OverviewStreakCache: @unchecked Sendable {
  static let shared = OverviewStreakCache()
  static let localChangeSeqKey = "local_change_seq"

  private struct Key: Equatable {
    let localChangeSeq: Int64
    let today: String
    let timezone: String?
  }

  private final class Entry {
    let key: Key
    let value: Overview.CompletionStreak
    init(_ key: Key, _ value: Overview.CompletionStreak) {
      self.key = key
      self.value = value
    }
  }

  private let lock = NSLock()
  /// Weakly keyed on the `Database` connection: the slot drops when the
  /// connection deallocates, so a freed store leaves nothing behind for a later
  /// store to inherit.
  private let slots = NSMapTable<Database, Entry>.weakToStrongObjects()

  /// Return the cached streak when the key matches the current connection
  /// state, else `compute()` and store the result. The lock is released before
  /// `compute` runs so a slow fold never blocks readers of other connections;
  /// at worst two readers of the same connection both compute and the later
  /// store wins (the value is identical for a given key, so this is harmless).
  func value(
    _ db: Database, today: String, timezone: String?,
    compute: (Database) throws -> Overview.CompletionStreak
  ) throws -> Overview.CompletionStreak {
    let seq =
      try Int64.fetchOne(
        db, sql: "SELECT value FROM local_counters WHERE name = ?1",
        arguments: [Self.localChangeSeqKey]) ?? 0
    let key = Key(localChangeSeq: seq, today: today, timezone: timezone)

    lock.lock()
    if let cached = slots.object(forKey: db), cached.key == key {
      lock.unlock()
      return cached.value
    }
    lock.unlock()

    let computed = try compute(db)

    lock.lock()
    slots.setObject(Entry(key, computed), forKey: db)
    lock.unlock()
    return computed
  }

  /// Drop this connection's cached streak. Required after a mutation path that
  /// changes completion/task state WITHOUT bumping `local_change_seq` — namely
  /// inbound sync apply, which mutates `habit_completions` / task status in the
  /// same process that renders the overview. Without this, a peer's completion
  /// landing via sync would leave the `local_change_seq`-keyed slot unchanged and
  /// the next read would return the pre-sync streak.
  func invalidate(_ db: Database) {
    lock.lock()
    slots.removeObject(forKey: db)
    lock.unlock()
  }
}
