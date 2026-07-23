/// Controls what provider calendar data Lorvex and connected AI/MCP clients can
/// see on this device. It is stored locally in `device_state` under the key
/// `calendar_ai_access_mode`; there is no synced or UserDefaults copy.
///
/// The `rawValue` is the canonical lower-snake-case string written to
/// `device_state` (matching ``asString``). The three tiers:
/// - `off` — provider data contributes nothing to Lorvex or AI/planning reads.
/// - `busyOnly` — provider occupancy contributes to blocking/planning, but
///   detail fields (title, location, description) are redacted.
/// - `fullDetails` — provider detail fields are passed through unmodified.
public enum CalendarAiAccessMode: String, Sendable, Hashable, Codable, CaseIterable {
  case off = "off"
  case busyOnly = "busy_only"
  case fullDetails = "full_details"

  /// Strict parser used by writers that surface validation errors back to
  /// callers (CLI, MCP). Trims surrounding whitespace, then returns `nil` for
  /// unrecognized values so each surface can wrap the failure in its own error.
  public static func parseStrict(_ s: String) -> CalendarAiAccessMode? {
    CalendarAiAccessMode(rawValue: s.trimmingCharacters(in: .whitespaces))
  }

  /// Serialize to the canonical string form.
  public var asString: String { rawValue }

  /// Whether provider events should be included at all (i.e. not `off`).
  public var includesProvider: Bool {
    self != .off
  }

  /// Whether provider event detail fields (title, location, description,
  /// person_name) should be passed through unredacted.
  public var includesDetails: Bool {
    self == .fullDetails
  }

  /// Ordinal exposure rank: `off`(0) < `busyOnly`(1) < `fullDetails`(2). A move
  /// to a strictly lower rank is a privacy downgrade: it reduces what provider
  /// data is exposed, so any richer data already mirrored under the prior tier
  /// must be purged rather than left at rest.
  public var detailRank: Int {
    switch self {
    case .off: return 0
    case .busyOnly: return 1
    case .fullDetails: return 2
    }
  }

  /// Whether moving from `self` to `newMode` reduces detail exposure — i.e. a
  /// downgrade that can strand previously-mirrored provider detail.
  public func reducesDetail(to newMode: CalendarAiAccessMode) -> Bool {
    newMode.detailRank < detailRank
  }

  /// The spec-defined default: `busyOnly`.
  public static let defaultMode: CalendarAiAccessMode = .busyOnly
}

/// Resolution-type vocabulary written into `sync_conflict_log` rows. Every LWW
/// outcome, tombstone-vs-upsert decision, content truncation, and dropped-shadow
/// path resolves to one of these — Settings → Sync → Conflicts buckets by exactly
/// this set, so any silent drop that doesn't write a row here is invisible to
/// operators.
public enum ResolutionName {
  public static let lww = "lww"
  /// Duplicate-entity convergence: two rows sharing a secondary dedup constraint
  /// are collapsed (min id wins, loser tombstoned with redirect) with one row
  /// emitted per dropped duplicate; `entity_type` distinguishes the source. Covers
  /// the `tag` / `habit` `lookup_key` merges and the `habit_reminder_policy`
  /// `(habit_id, reminder_time)` merge.
  public static let tagMerge = "tag_merge"
  public static let fkStalled = "fk_stalled"
  public static let fkUnresolved = "fk_unresolved"
  /// A pending-inbox row (an FK-orphaned or unknown-entity_type record) aged past
  /// the full-resync horizon and was hard-deleted by the GC. A device this far
  /// behind can no longer apply the record incrementally, so the loss is recorded
  /// here and flagged in `sync_checkpoints` (see
  /// ``SyncNaming/reseedRequiredCheckpointKey``) rather than dropped silently.
  public static let reseedRequired = "reseed_required"
  /// Pending inbox entry discarded after exceeding per-entry retry cap.
  public static let pendingInboxExhausted = "pending_inbox_exhausted"
  /// Task-dependency edge broken during apply because it would have introduced
  /// a cycle.
  public static let cycleBreak = "cycle_break"
  /// Upsert payload exceeded a domain byte cap and was truncated at apply
  /// rather than rejected, with a conflict-log entry recording what was clipped.
  public static let contentTruncated = "content_truncated"
  /// A delete envelope arrived for an entity that is already a merge loser; the
  /// delete is dropped rather than propagated to the winner.
  public static let redirectedDeleteDropped = "redirected_delete_dropped"
  /// An upsert envelope was rejected because the local tombstone is newer (or
  /// equal-versioned).
  public static let tombstoneWins = "tombstone_wins"
  /// An upsert envelope was strictly newer than a local delete tombstone, so
  /// the tombstone was removed and the upsert applied.
  public static let upsertWinsOverDelete = "upsert_wins_over_delete"
}

/// Sync-envelope operation names and retention windows shared across transport,
/// GC, and reseed paths.
public enum SyncNaming {
  // Sync-envelope operation names.
  public static let opUpsert = "upsert"
  public static let opDelete = "delete"

  /// Device-local forensic audit emitted when coalescing discards an outbound
  /// delete before it ever reaches CloudKit. It must never be assigned to an
  /// iCloud account or included in a candidate-generation audit baseline.
  public static let localAuditCoalescedDeleteDropped =
    "sync.outbox.coalesced_delete_dropped"

  /// Contractual maximum delete-recovery window. Once a CloudKit-owned server
  /// timestamp proves a confirmed tombstone is older than this, a new immutable
  /// generation may omit that exact death marker. A database can union with that
  /// generation only when its completed baseline witness is strictly later than
  /// the published cutoff; otherwise it adopts the generation authoritatively.
  /// Device wall time never authorizes compaction. See `SYNC_APPLY_SEMANTICS.md`.
  public static let tombstoneMaxRetentionDays: UInt32 = 365

  /// Pending inbox envelopes older than this trigger reseed_required. Separate
  /// from tombstone GC (which uses version-domain watermark).
  public static let fullResyncHorizonDays: UInt32 = 90

  /// `sync_checkpoints` key set to `"true"` when the horizon GC has hard-deleted
  /// an expired pending-inbox orphan row (see ``ResolutionName/reseedRequired``;
  /// budget-exempt HOLD rows are retained, not reaped, and never set this). The
  /// sync transport observes it at cycle start and performs the reseed recovery,
  /// and the host surfaces it while set; the value carries no user content and
  /// is device-local like every other checkpoint.
  public static let reseedRequiredCheckpointKey = "reseed_required"

  /// Hard safeguard: maximum ai_changelog entries before forced cleanup. NOT a
  /// primary retention rule — the time window is primary.
  public static let auditMaxEntriesSafeguard: UInt32 = 10_000
}
