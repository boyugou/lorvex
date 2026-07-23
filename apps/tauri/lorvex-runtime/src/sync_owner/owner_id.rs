//! Per-process unique sync-owner identifier.
//!
//! Production lease acquirers used to bind static role strings
//! (`"desktop_app"`, `"cli"`) directly as `owner_id`. The acquire SQL
//! admits a re-acquire when the row's `owner_id` matches the new
//! `owner_id` (so the same process can renew its own lease via the
//! `OR owner_id = excluded.owner_id` arm), and `release_sync_owner`
//! deletes any row matching `(lease_name, owner_id)`. Two processes
//! that both bind the same static role string would therefore
//! collide on every step of the protocol — and a stale `Drop` from
//! process A whose lease had expired could delete a freshly-acquired
//! row that process B owns.
//!
//! [`process_owner_id`] solves this by composing `"<role>:<UUIDv7>"`
//! where the UUIDv7 suffix is minted exactly once per process via
//! `OnceLock`. The same process gets the same string for the lifetime
//! of the run — so the SQL `owner_id = excluded.owner_id` re-entry
//! arm still admits a same-process renew — but two processes
//! (regardless of static role) generate effectively-distinct
//! suffixes (122 bits of post-timestamp entropy) and never collide.
//!
//! The returned `&'static str` is leaked once on first call per role
//! (at most 2 leaks per process: `desktop_app` and `cli`), so call
//! sites don't pay an allocation per acquire/release.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

/// Wrap a static role string with a per-process UUIDv7 suffix.
///
/// `role` must be `'static` so the cache key is comparable without
/// hashing arbitrary `&str` lifetimes; production roles are
/// `&'static str` literals already (`"desktop_app"`, `"cli"`).
///
/// The first call per role mints `<role>:<UUIDv7>`, leaks it onto the
/// heap (`Box::leak`), and caches the resulting `&'static str` for
/// subsequent calls. The leak is intentional and bounded (one entry
/// per distinct role per process) so the runtime's lease-acquisition
/// path never pays a `format!` per call.
pub fn process_owner_id(role: &'static str) -> &'static str {
    static CACHE: OnceLock<Mutex<HashMap<&'static str, &'static str>>> = OnceLock::new();
    let map = CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    let mut guard = map
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if let Some(&owned) = guard.get(role) {
        return owned;
    }
    let suffix = process_instance_suffix();
    let composed = format!("{role}:{suffix}");
    let leaked: &'static str = Box::leak(composed.into_boxed_str());
    guard.insert(role, leaked);
    leaked
}

fn process_instance_suffix() -> &'static str {
    static SUFFIX: OnceLock<String> = OnceLock::new();
    SUFFIX
        .get_or_init(lorvex_domain::entity_id::new_entity_id_string)
        .as_str()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn process_owner_id_is_role_prefixed() {
        let id = process_owner_id("desktop_app");
        assert!(
            id.starts_with("desktop_app:"),
            "expected role prefix, got {id:?}"
        );
    }

    #[test]
    fn process_owner_id_is_stable_across_calls_for_same_role() {
        let a = process_owner_id("desktop_app");
        let b = process_owner_id("desktop_app");
        assert_eq!(a, b);
        // Same `&'static str` slice — caching means we hand back the
        // same leaked allocation each call, not a fresh equal string.
        assert_eq!(a.as_ptr(), b.as_ptr());
    }

    #[test]
    fn process_owner_id_distinguishes_roles_within_a_process() {
        let app = process_owner_id("desktop_app");
        let cli = process_owner_id("cli");
        assert_ne!(app, cli);
        // Both share the same suffix because they're minted from the
        // same process-instance UUIDv7 — only the role prefix differs.
        let app_suffix = app.split_once(':').map(|(_, s)| s);
        let cli_suffix = cli.split_once(':').map(|(_, s)| s);
        assert_eq!(app_suffix, cli_suffix);
        assert!(app_suffix.is_some(), "owner id must contain a colon");
    }

    #[test]
    fn process_instance_suffix_is_uuidv7_shape() {
        let suffix = process_instance_suffix();
        assert_eq!(suffix.len(), 36, "UUIDv7 string is 36 chars");
        assert_eq!(suffix.chars().filter(|&c| c == '-').count(), 4);
    }
}
