/// Shared eligibility rule for every trusted tombstone-compaction path.
///
/// A permanent redirect can resolve only while its terminal target has either
/// a live row or a death marker. Once the target is deleted, its tombstone is
/// therefore part of the permanent alias graph, not an independently
/// recoverable delete. Retaining every directly referenced target is a simple
/// closure proof for an arbitrarily long redirect chain: every intermediate
/// node and the terminal node is the direct target of its predecessor.
///
/// Every query using this fragment must alias `sync_tombstones` as
/// `tombstone`. Keeping one literal predicate prevents snapshot enumeration,
/// transition backfill, and physical reclamation from drifting apart.
enum TombstoneCompactionPolicy {
  static let isPermanentRedirectTargetSQL = """
    EXISTS (
      SELECT 1
      FROM sync_entity_redirects AS permanent_redirect
      WHERE permanent_redirect.source_type = tombstone.entity_type
        AND permanent_redirect.target_id = tombstone.entity_id
    )
    """
}
