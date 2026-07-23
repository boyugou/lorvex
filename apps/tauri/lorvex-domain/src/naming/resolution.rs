//! Resolution-type vocabulary written into `sync_conflict_log` rows.
//! Every LWW outcome, tombstone-vs-upsert decision, content truncation,
//! attendee-collision arbitration, and dropped-shadow path resolves to
//! one of the constants below — Settings → Sync → Conflicts buckets
//! by exactly this set, so any silent drop that doesn't write a row
//! here is invisible to operators.

pub const RESOLUTION_LWW: &str = "lww";
pub const RESOLUTION_TAG_MERGE: &str = "tag_merge";
pub const RESOLUTION_RECURRENCE_DEDUP: &str = "recurrence_dedup";
pub const RESOLUTION_FK_STALLED: &str = "fk_stalled";
pub const RESOLUTION_FK_UNRESOLVED: &str = "fk_unresolved";
pub const RESOLUTION_RESEED_REQUIRED: &str = "reseed_required";
/// Pending inbox entry discarded after exceeding per-entry retry cap —
/// means the FK target never arrived and full-horizon reseed is a
/// heavier hammer than giving up on a single entry (#2463).
pub const RESOLUTION_PENDING_INBOX_EXHAUSTED: &str = "pending_inbox_exhausted";
/// Task-dependency edge broken during apply because it would have
/// introduced a cycle. The canonical resolution vocabulary lives
/// here (per #2248) so the apply subtree in
/// `lorvex-sync/src/apply/edge/` shares one source of truth instead
/// of carrying inline literals.
pub const RESOLUTION_CYCLE_BREAK: &str = "cycle_break";
/// Memory upsert payload exceeded `MAX_MEMORY_CONTENT_LENGTH` (#2429)
/// or any aggregate free-text column exceeded a domain byte cap —
/// truncated at apply rather than rejected so
/// the data still lands, with a sync_conflict_log entry telling the
/// user what was clipped. Shared between #2429 and #2431 so Settings
/// → Sync renders a single "content truncated on receive" bucket
/// across entity types.
pub const RESOLUTION_CONTENT_TRUNCATED: &str = "content_truncated";

/// A delete envelope arrived for an entity that's already a merge
/// loser (the local tombstone redirects to a winner). Such an envelope
/// can only have been authored by a peer that didn't yet know about
/// the merge — a peer that observed the merge would have routed any
/// subsequent delete to the merge winner directly. We
/// drop the delete rather than propagating it to the winner, since
/// "delete the merge loser" semantically means "the loser identity
/// no longer exists" — which is already the case post-merge — and
/// applying the delete to the winner would be unauthorized data
/// destruction. Logged so the diagnostics surface sees the drop.
pub const RESOLUTION_REDIRECTED_DELETE_DROPPED: &str = "redirected_delete_dropped";

/// An upsert envelope was rejected because the local tombstone for
/// that entity is newer (or equal-versioned) than the envelope.
/// This resolution_type makes the tombstone-vs-upsert decision
/// auditable in Settings → Diagnostics. Returning `Skipped` with a
/// free-form reason and no `sync_conflict_log` row would let the
/// dropped upsert vanish — the diagnostics surface only displays
/// conflict_log entries.
pub const RESOLUTION_TOMBSTONE_WINS: &str = "tombstone_wins";

/// An upsert envelope was strictly newer than a local delete tombstone,
/// so the apply pipeline removed the tombstone and applied the upsert
/// (concurrent-update wins over concurrent-delete). Logged on both the
/// non-redirect and redirect-target branches so an operator looking at
/// "why did this previously-deleted entity reappear?" sees an audit
/// trail in Settings → Diagnostics. Without this entry, every other
/// LWW outcome wrote a `sync_conflict_log` row but the upsert-wins-
/// over-delete branch silently undid a real DELETE the cluster had
/// agreed on.
pub const RESOLUTION_UPSERT_WINS_OVER_DELETE: &str = "upsert_wins_over_delete";

/// A forward-compat payload shadow was reaped during
/// `promote_payload_shadows` because the live local row has a
/// strictly newer version than the shadow's `base_version`. Logging
/// this resolution_type ensures the diagnostics panel sees every
/// dropped shadow. Falling through the SQL `>=` gate inside
/// `apply_entity_with_version_mode(_, true)` and silently refusing
/// the INSERT would drop the shadow's preserved unknown fields with
/// no diagnostic. Surfaces the
/// permanently-lost forward-compat payload.
pub const RESOLUTION_SHADOW_OBSOLETE: &str = "shadow_obsolete";

/// a `calendar_event` upsert envelope contained two or
/// more attendee entries that collided after the canonical
/// `trim().to_lowercase()` email normalization. The apply pipeline
/// keeps a single deterministic winner per email (selected by
/// lexicographically-smallest canonical-JSON of the entry) and emits
/// one `attendee_email_collision` row per dropped entry so the
/// audit trail names exactly which attendee metadata was lost.
/// The deterministic-winner discipline is required because a naive
/// `INSERT OR IGNORE` for the primary row paired with pushing the
/// duplicate's surplus extras into `attendee_shadow_rows` would let
/// the LEFT JOIN in `replace_attendee_shadows` pair the LATER extras
/// with the EARLIER attendee, silently fusing two peers' metadata
/// under a single row with zero diagnostic surface.
pub const RESOLUTION_ATTENDEE_EMAIL_COLLISION: &str = "attendee_email_collision";

/// a payload-shadow merge crosses two different
/// entity types (loser is a `task`, winner becomes a `memory`,
/// etc.) and the loser's forward-compat unknown-key payload
/// cannot be carried across the schema boundary safely — the
/// owned-keys set is per-entity-type, so what's "known" on one
/// side is "unknown forward-compat" on the other and vice versa.
/// `merge_shadow_into_redirect` drops the loser shadow rather
/// than misapplying its fields onto the winner row. The drop must
/// route through this resolution_type rather than a bare
/// `error_logs` warn entry — that surface is noisy and not
/// reflected in the dedicated Settings → Sync → Conflicts panel.
/// Promoting the drop into the canonical conflict-log feed lets an
/// operator see it alongside every other LWW / tombstone / merge
/// outcome, and the dropped raw_payload is preserved (scrubbed) for
/// inspection.
pub const RESOLUTION_CROSS_TYPE_REDIRECT_DROP: &str = "cross_type_redirect_drop";
