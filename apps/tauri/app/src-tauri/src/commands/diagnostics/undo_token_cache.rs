//! In-process cache mapping task id → serialized `UndoToken` JSON for
//! the short undo window.
//!
//! Why this exists: the Changelog view exposes the per-row "Undo"
//! affordance that also lives on the success toast from
//! complete/cancel/update. The UndoToken — which carries the
//! pre-mutation state required to restore the task — is never
//! persisted for Tauri-originated writes; it's only returned in-memory
//! to the caller that triggered the mutation. The changelog surface
//! has no in-memory reference to that token, so this cache parks the
//! serialized token in process memory for the lifetime of the undo
//! window (the token's own `expires_at`). An app restart invalidates
//! the cache, which is fine — the undo window is seconds long.
//!
//! The store is keyed by task id: the changelog query looks up
//! `ai_changelog.entity_id` here to find the token for a row's Undo
//! button. A burst of mutations on the same task keeps only the most
//! recent token — undoing the latest mutation is the only offer the
//! toast makes too.

use std::collections::HashMap;
use std::sync::Mutex;
use std::sync::OnceLock;

use chrono::{DateTime, Utc};

#[derive(Debug, Clone)]
struct CachedUndoToken {
    /// Serialized `UndoToken` JSON — the exact string that the
    /// existing `undo_task_lifecycle` command accepts.
    token_json: String,
    /// RFC 3339 timestamp at which the undo window closes. Matches the
    /// `expires_at` field baked into the serialized token.
    expires_at: DateTime<Utc>,
}

fn cache() -> &'static Mutex<HashMap<String, CachedUndoToken>> {
    static CACHE: OnceLock<Mutex<HashMap<String, CachedUndoToken>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Register a serialized undo token for the given task id. Called from
/// the task-lifecycle commands right after `build_undo_token` so the
/// changelog surface can look up the token while the undo window is
/// still open.
///
/// `expires_at_rfc3339` must be the same string that was baked into the
/// token's `expires_at` field (i.e. the window boundary). Malformed
/// timestamps are silently dropped — the undo path degrades to "no
/// undo available" rather than panicking on an impossible input.
pub fn register(task_id: &str, token_json: &str, expires_at_rfc3339: &str) {
    if task_id.is_empty() {
        return;
    }
    let Ok(expires_at) = DateTime::parse_from_rfc3339(expires_at_rfc3339) else {
        return;
    };
    let expires_at = expires_at.with_timezone(&Utc);
    let entry = CachedUndoToken {
        token_json: token_json.to_string(),
        expires_at,
    };
    let Ok(mut guard) = cache().lock() else {
        return;
    };
    guard.insert(task_id.to_string(), entry);
    prune_expired(&mut guard);
}

/// Look up the serialized undo token JSON for a given task id. Returns
/// `None` if the token was never registered, has already been
/// consumed, or has passed its expiry.
///
/// Lookup also opportunistically prunes expired siblings so the cache
/// stays bounded under churn without a dedicated sweeper.
pub fn lookup(task_id: &str) -> Option<String> {
    if task_id.is_empty() {
        return None;
    }
    let mut guard = cache().lock().ok()?;
    prune_expired(&mut guard);
    guard.get(task_id).map(|entry| entry.token_json.clone())
}

/// Remove the cached token for a task — called after a successful
/// undo so a double-click on stale UI can't replay the same token.
pub fn consume(task_id: &str) {
    if task_id.is_empty() {
        return;
    }
    let Ok(mut guard) = cache().lock() else {
        return;
    };
    guard.remove(task_id);
}

fn prune_expired(map: &mut HashMap<String, CachedUndoToken>) {
    let now = Utc::now();
    map.retain(|_, entry| entry.expires_at > now);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rfc(offset_secs: i64) -> String {
        (Utc::now() + chrono::Duration::seconds(offset_secs))
            .to_rfc3339_opts(chrono::SecondsFormat::Micros, true)
    }

    #[test]
    fn register_and_lookup_roundtrip() {
        let task = "task-roundtrip-1";
        register(task, "{\"x\":1}", &rfc(10));
        let got = lookup(task);
        assert_eq!(got.as_deref(), Some("{\"x\":1}"));
        consume(task);
        assert!(lookup(task).is_none());
    }

    #[test]
    fn lookup_returns_none_for_expired_entries() {
        let task = "task-expired-1";
        register(task, "{\"stale\":true}", &rfc(-1));
        assert!(lookup(task).is_none());
    }

    #[test]
    fn empty_task_id_is_rejected() {
        register("", "{\"x\":1}", &rfc(10));
        assert!(lookup("").is_none());
    }

    #[test]
    fn malformed_expiry_is_dropped_silently() {
        let task = "task-malformed-1";
        register(task, "{\"x\":1}", "not-a-timestamp");
        assert!(lookup(task).is_none());
    }
}
