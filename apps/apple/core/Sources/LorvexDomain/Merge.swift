/// Pure merge policy for LWW resolution and tag merge.
///
/// All functions are pure — no IO, no database. They operate on domain
/// types (``Hlc``, entity IDs) and return deterministic outcomes.
public enum MergeOutcome: Sendable, Equatable {
  /// Local version wins (is newer or equal).
  case localWins
  /// Remote version wins (is strictly newer).
  case remoteWins
}

public enum Merge {
  /// Compare two HLC versions. If the remote is strictly greater, it wins.
  /// Ties resolve to local so idempotent re-applies are no-ops.
  public static func resolveLww(local: Hlc, remote: Hlc) -> MergeOutcome {
    remote > local ? .remoteWins : .localWins
  }

  /// Tag merge winner: byte-lex min over the two ids. UUIDv7 sorts
  /// chronologically, so the earlier-created tag wins. Returns
  /// `(winner, loser)`.
  ///
  /// Compares via UTF-8 to keep the contract byte-lex; Swift's default
  /// `String <` is Unicode-normalization-aware and would not preserve byte
  /// order on non-ASCII peers.
  public static func tagMergeWinner(_ idA: String, _ idB: String) -> (String, String) {
    if !idB.utf8.lexicographicallyPrecedes(idA.utf8) {
      // idA <= idB
      return (idA, idB)
    } else {
      return (idB, idA)
    }
  }
}
