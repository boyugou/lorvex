/// LorvexSync — the CloudKit-envelope sync layer: wire-format encoding,
/// canonicalization, outbox/coalesce/enqueue, tombstones, conflict resolution,
/// and the apply pipeline.
public enum LorvexSync {
  /// Placeholder constant giving the target a concrete public symbol.
  public static let version: UInt32 = 1
}
