import GRDB
import LorvexDomain

extension ChangelogRetentionPolicy {
  /// Read the active/unbound audit-retention control-plane state. A malformed
  /// state or read failure degrades to ``maximum`` (never a silent purge).
  /// Safe to call inside a mutation transaction.
  public static func read(_ db: Database) -> ChangelogRetentionPolicy {
    (try? AuditRetentionFrontier.currentPolicy(db)) ?? .maximum
  }
}
