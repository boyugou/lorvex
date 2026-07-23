//! Post-UPDATE bookkeeping shared by the simple-PK and composite-PK
//! stamp paths: typed-or-byte LWW domination check + the three-arm
//! classifier that converts an existing-version `Option<Option<String>>`
//! lookup into the canonical [`VersionStampError`].

use lorvex_domain::naming::EntityKind;

use super::error::VersionStampError;

/// Decide whether the row's persisted `existing_version` strictly
/// dominates the stamp version we tried to write — used by both the
/// simple-PK and composite-PK paths after the LWW-gated UPDATE
/// reports zero rows affected.
///
/// Strategy: parse both sides. If both parse, compare typed (the
/// `Hlc` `Ord` impl matches the SQL byte order for canonical
/// strings, and the typed compare future-proofs against any future
/// HLC shape change). If parse fails on either side, fall back to
/// byte compare — the same ordering the SQL gate just used — and
/// surface `Superseded` whenever the existing string strictly beat
/// the stamp on bytes.
///
/// Why surface `Superseded` instead of `Ok(())` on the byte-fallback
/// path? If the row carries a stale-shape literal (`'v1'`, `'seed'`,
/// `'test_ver'`) the SQL byte-compare is what governed the refusal,
/// and since ASCII letters sort above digits, the tainted row beat
/// the canonical stamp at the gate. Silently returning `Ok(())`
/// would let the caller's outbox enqueue ship an envelope at the
/// canonical stamp version while the row's `version` column stayed
/// tainted — exactly the "outbox row carries an HLC that disagrees
/// with the row's version column" drift that the typed `Superseded`
/// error exists to prevent. The narrow `Ok(())` path remains:
/// `existing == stamp` (a concurrent writer raced us at the exact
/// same representation) is the only harmless case.
fn existing_version_dominates(existing_version: &str, stamp_version: &str) -> bool {
    match (
        lorvex_domain::hlc::Hlc::parse(existing_version),
        lorvex_domain::hlc::Hlc::parse(stamp_version),
    ) {
        (Ok(existing_hlc), Ok(stamp_hlc)) => existing_hlc > stamp_hlc,
        _ => existing_version > stamp_version,
    }
}

/// Map a runtime `&str` entity type back to its `&'static str` constant
/// so `VersionStampError::Superseded` can carry it without an
/// allocation.
///
/// Routes through [`EntityKind`] for a single parse-then-stringify
/// instead of a 22-arm match that duplicates the entity-type
/// registry; unrecognized values fall through to an `"unknown"`
/// sentinel.
fn static_entity_type(entity_type: &str) -> &'static str {
    EntityKind::parse(entity_type).map_or("unknown", |k| k.as_str())
}

/// Classify the LWW-gated UPDATE-affected-zero-rows case into the
/// typed `VersionStampError` that callers must observe to avoid
/// silently shipping a sync envelope at a stale local version.
///
/// Identical post-UPDATE bookkeeping is required for both the
/// simple-PK and composite-PK paths; each open-coded the
/// same three-arm match (`Some(Some)` → Superseded-or-Ok,
/// `Some(None)` → benign no-op, `None` → EntityNotFound) on top of a
/// distinct `read_version` SELECT. Folding the post-read classifier
/// here keeps both call sites a single line and pins the contract:
/// `Some(Some(s))` is the only arm that can fault as `Superseded`.
pub(super) fn classify_post_update_existing(
    existing: Option<Option<String>>,
    entity_type: &str,
    entity_id: &str,
    stamp_version: &str,
) -> Result<(), VersionStampError> {
    match existing {
        Some(Some(existing_version)) => {
            // The SQL UPDATE predicate `?1 > version` byte-compares
            // the stamp version against the row's `version` column.
            // If the row is well-formed and lost on byte-compare,
            // we route through the typed `Hlc` compare via
            // `existing_version_dominates` for the
            // typed-or-byte-fallback comparison and rationale.
            if existing_version_dominates(&existing_version, stamp_version) {
                return Err(VersionStampError::Superseded {
                    entity_type: static_entity_type(entity_type),
                    entity_id: entity_id.to_string(),
                    existing_version,
                });
            }
            // Reaching this branch with `Some(Some(existing))` means
            // (a) the SQL gate `?1 > version` reported zero rows, AND
            // (b) the typed/byte compare did not declare existing as
            // strictly greater. The only string for which both hold is
            // `existing == stamp_version` — i.e. another writer raced
            // us at the EXACT same HLC. Equal HLCs imply equal
            // `(physical_ms, counter, device_suffix)`; same device
            // generating identical HLCs back-to-back means the
            // canonical `HlcState::generate` invariant (counter
            // monotone-bumps within the same `physical_ms`) is broken
            // OR the HLC state was reset mid-process. Loud in debug
            // (`debug_assert!`) so a future regression in the HLC
            // state machine fires immediately during dev/CI; release
            // builds keep the historic harmless-no-op contract so a
            // peer race never forces the production write surface
            // into a panic.
            debug_assert!(
                existing_version == stamp_version,
                "version_stamp post-UPDATE classifier reached the harmless arm with \
                 existing={existing_version:?} != stamp={stamp_version:?} for \
                 {entity_type}:{entity_id}; HLC compare invariant violated",
            );
            Ok(())
        }
        Some(None) => {
            // Row exists with NULL version. The UPDATE predicate
            // `?1 > version` should have matched it; reaching here
            // with NULL implies a concurrent writer just stamped the
            // exact same version we tried — harmless. Treat as a
            // benign no-op so callers without a Superseded recovery
            // path still make progress.
            Ok(())
        }
        None => Err(VersionStampError::EntityNotFound {
            entity_type: entity_type.to_string(),
            entity_id: entity_id.to_string(),
        }),
    }
}
