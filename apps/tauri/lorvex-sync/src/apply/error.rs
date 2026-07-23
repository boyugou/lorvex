//! Apply-pipeline error and result plumbing.
//!
//! The typed `ApplyResult` / `ApplyError` enums and their `From`
//! conversions live in one inspectable place. The `REDIRECT_CHAIN_CAP`
//! constant and the `DeferralReason` enum used by the pending-inbox
//! path also live here because they're part of the same
//! result-and-error vocabulary.

use std::fmt;

use lorvex_domain::hlc::Hlc;
use lorvex_domain::naming::EntityKind;
use lorvex_sync_payload::payload_shadow::MAX_RAW_PAYLOAD_JSON_BYTES;

/// Typed reason for deferring an envelope to the pending inbox.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DeferralReason {
    /// The envelope's payload_schema_version is too far ahead of local.
    SchemaTooNew {
        remote_version: u32,
        local_version: u32,
    },
    /// A required foreign-key dependency is not yet present locally.
    MissingDependency {
        entity_type: EntityKind,
        entity_id: String,
    },
    /// An aggregate-level invariant guard refused the envelope on
    /// the receiving device — currently only the at-least-one-list
    /// rule fires this branch (deleting the last remaining list
    /// would leave the device with zero lists, breaking task
    /// creation). The envelope sits in the pending inbox until a
    /// future apply pass loosens the invariant (another list
    /// arrives), at which point the drain re-runs the delete and it
    /// succeeds. Without this deferral, the dispatcher would write a
    /// tombstone at the envelope's HLC while leaving the row alive,
    /// silently blocking every future re-upsert from any peer (the
    /// tombstone-vs-upsert gate uses
    /// `tombstone.version >= envelope.version`, and a peer concurrent
    /// edit at a lower HLC than the delete would lose).
    AggregateInvariantBlocked {
        entity_type: EntityKind,
        entity_id: String,
        invariant: &'static str,
    },
}

impl std::fmt::Display for DeferralReason {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::SchemaTooNew {
                remote_version,
                local_version,
            } => {
                write!(f, "payload_schema_version {remote_version} is too far ahead (local max: {local_version})")
            }
            Self::MissingDependency {
                entity_type,
                entity_id,
            } => {
                write!(f, "missing dependency: {entity_type}/{entity_id}")
            }
            Self::AggregateInvariantBlocked {
                entity_type,
                entity_id,
                invariant,
            } => {
                write!(
                    f,
                    "aggregate invariant '{invariant}' refused envelope for \
                     {entity_type}/{entity_id} — will retry once the invariant relaxes"
                )
            }
        }
    }
}

/// Result of applying a single sync envelope.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ApplyResult {
    /// The envelope was applied successfully.
    Applied,
    /// The envelope was skipped (local version is newer or equal).
    ///
    /// `winner_version` carries the typed [`Hlc`] that beat the
    /// envelope when the skip was driven by an LWW comparison
    /// (local-wins, tombstone-wins, redirect-target LWW). `None` for
    /// skips that have no programmatic winner, such as local-only
    /// entity filters and already-tombstoned-delete no-ops, so
    /// downstream consumers don't have to scrape the free-form
    /// `reason` string to learn what beat the envelope.
    Skipped {
        reason: String,
        winner_version: Option<Hlc>,
    },
    /// The envelope was deferred to the pending inbox.
    Deferred { reason: DeferralReason },
    /// The envelope was remapped via tombstone redirect.
    Remapped {
        from_entity_id: String,
        to_entity_id: String,
    },
}

/// cap on tombstone-redirect chain hops.
///
/// `apply_envelope` and `promote_payload_shadows` both walk the
/// redirect chain (`tombstones.redirect_entity_id`) when resolving an
/// inbound envelope to its current target. Bounded so a malicious or
/// corrupt redirect cycle can't spin forever — at depth `> CAP` we
/// surface `ApplyError::TombstoneRedirectCycle` and skip apply.
///
/// The two call sites hardcoded `8` separately; if one was
/// bumped without the other, redirect-walking semantics drifted. One
/// canonical const eliminates that risk.
pub(crate) const REDIRECT_CHAIN_CAP: usize = 8;

/// Errors that can occur during envelope application.
#[derive(Debug)]
pub enum ApplyError {
    /// The apply boundary was called without the required outer transaction.
    TransactionRequired,
    /// HLC parsing failure.
    InvalidVersion(String),
    /// Database error.
    Db(rusqlite::Error),
    /// Unknown entity type in envelope.
    UnknownEntityType(String),
    /// JSON payload parsing or field error.
    InvalidPayload(String),
    /// A non-SQL store-layer error (NotFound, Validation, Invariant, etc.).
    Store(lorvex_store::StoreError),
    /// A tombstone redirect chain looped back on a previously-visited
    /// entity_id (self-redirect or mutual A→B / B→A). Refusing to
    /// apply rather than blindly chasing the cap iterations and
    /// applying to a phantom target.
    TombstoneRedirectCycle {
        entity_type: String,
        entity_id: String,
    },
    /// a tombstone redirect chain exceeded the
    /// bounded `REDIRECT_CHAIN_CAP`.
    /// silently exited at the cap and applied the envelope at
    /// whatever intermediate id the loop had reached, NOT at the
    /// chain terminus — durably routing the apply to the wrong
    /// row. Distinct from `TombstoneRedirectCycle`: the chain may
    /// be acyclic but simply longer than the cap (a long sequence
    /// of merges across many devices). Surfaces with the chain's
    /// observed length and the last id reached so diagnostics can
    /// flag the rare deep-chain case for manual investigation.
    TombstoneRedirectChainTooDeep {
        entity_type: String,
        entity_id: String,
        chain_length: usize,
        terminal_id: String,
    },
    /// The envelope's operation is not legal for the addressed entity
    /// type — e.g. a `Delete` envelope targeting `ai_changelog`, an
    /// append-only audit stream that the writer never produces deletes
    /// for. A malicious or buggy peer authoring a
    /// delete-shaped envelope must be refused at the dispatcher; the
    /// changelog has no `version` column so the upstream LWW gate
    /// never fires for it, leaving deletes otherwise unguarded.
    InvalidOperation {
        entity_type: String,
        operation: String,
    },
    /// the redirect chase rewrote payload-FK identity
    /// fields across one or more hops and the canonical re-serialization
    /// of the mutated payload exceeded [`MAX_RAW_PAYLOAD_JSON_BYTES`].
    /// Without this gate, the apply pipeline would forward an
    /// over-sized payload into `apply_entity` / `finalize_payload_shadow`
    /// where the size check fires deep inside the storage boundary,
    /// producing a generic `Validation` error far from the actual
    /// cause (the multi-hop FK rewrite). Surfacing the limit here
    /// keeps the diagnostic adjacent to the redirect chain that
    /// produced the over-sized result.
    RedirectPayloadTooLarge {
        entity_type: EntityKind,
        entity_id: String,
        size_bytes: usize,
    },
}

impl fmt::Display for ApplyError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::TransactionRequired => write!(
                f,
                "apply_envelope must run inside an outer transaction (BEGIN IMMEDIATE)"
            ),
            Self::InvalidVersion(msg) => write!(f, "invalid version: {msg}"),
            Self::Db(e) => write!(f, "database error: {e}"),
            Self::UnknownEntityType(t) => write!(f, "unknown entity type: {t}"),
            Self::InvalidPayload(msg) => write!(f, "invalid payload: {msg}"),
            Self::Store(e) => write!(f, "store error: {e}"),
            Self::TombstoneRedirectCycle {
                entity_type,
                entity_id,
            } => write!(
                f,
                "tombstone redirect cycle for {entity_type} {entity_id}: \
                 a redirect chain looped back on a previously-visited id"
            ),
            Self::TombstoneRedirectChainTooDeep {
                entity_type,
                entity_id,
                chain_length,
                terminal_id,
            } => write!(
                f,
                "tombstone redirect chain too deep for {entity_type} {entity_id}: \
                 chain reached {chain_length} hops and was still redirecting at \
                 terminal id {terminal_id}"
            ),
            Self::InvalidOperation {
                entity_type,
                operation,
            } => write!(
                f,
                "invalid operation '{operation}' for entity type '{entity_type}'"
            ),
            Self::RedirectPayloadTooLarge {
                entity_type,
                entity_id,
                size_bytes,
            } => write!(
                f,
                "redirect chase produced an over-sized payload for {entity_type} {entity_id}: \
                 {size_bytes} bytes exceeds maximum of {MAX_RAW_PAYLOAD_JSON_BYTES} bytes"
            ),
        }
    }
}

impl std::error::Error for ApplyError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Db(e) => Some(e),
            Self::Store(e) => Some(e),
            _ => None,
        }
    }
}

impl From<rusqlite::Error> for ApplyError {
    fn from(e: rusqlite::Error) -> Self {
        Self::Db(e)
    }
}

impl From<lorvex_store::StoreError> for ApplyError {
    fn from(e: lorvex_store::StoreError) -> Self {
        match e {
            lorvex_store::StoreError::Sql(sql_err) => Self::Db(sql_err),
            other => Self::Store(other),
        }
    }
}

/// `PayloadError` originates from [`lorvex_sync_payload`] (#4350).
/// Re-classify via `StoreError::from` first so disk-full `Sql`
/// variants trip the breaker before landing as a typed `ApplyError`.
impl From<lorvex_sync_payload::PayloadError> for ApplyError {
    fn from(e: lorvex_sync_payload::PayloadError) -> Self {
        Self::from(lorvex_store::StoreError::from(e))
    }
}

impl From<serde_json::Error> for ApplyError {
    fn from(e: serde_json::Error) -> Self {
        Self::InvalidPayload(e.to_string())
    }
}

impl From<lorvex_domain::hlc::HlcParseError> for ApplyError {
    fn from(e: lorvex_domain::hlc::HlcParseError) -> Self {
        Self::InvalidVersion(e.to_string())
    }
}
