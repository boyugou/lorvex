//! Mutation descriptors for the `calendar_subscriptions` table.
//!
//! Each descriptor implements [`crate::mutation::Mutation`] so every
//! surface that writes subscription rows (Tauri IPC, sync apply, CLI)
//! plugs the same row-level contract into its surface executor. The
//! workflow crate owns the SQL UPDATE / INSERT / DELETE, the HLC stamp
//! through the per-mutation [`HlcSession`], and the payload shape
//! constructed via [`lorvex_store::payload_loaders`]. The surface
//! adapter's finalizer owns sync-outbox enqueue, event-bus broadcast,
//! and `local_change_seq` bump.
//!
//! ## Operation catalog
//!
//! | Descriptor                                  | Op       | Entity                  |
//! | ------------------------------------------- | -------- | ----------------------- |
//! | [`AddCalendarSubscriptionMutation`]         | `upsert` | `calendar_subscription` |
//! | [`RemoveCalendarSubscriptionMutation`]      | `delete` | `calendar_subscription` |
//! | [`ToggleCalendarSubscriptionMutation`]      | `upsert` | `calendar_subscription` |
//! | [`UpdateCalendarSubscriptionColorMutation`] | `upsert` | `calendar_subscription` |
//!
//! Reads are not orchestrated through `Mutation` — surfaces call
//! [`list_calendar_subscriptions`] directly with their connection.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_CALENDAR_SUBSCRIPTION, OP_DELETE, OP_UPSERT};
use lorvex_domain::sync_timestamp_now;
use lorvex_store::StoreError;
use rusqlite::{params, Connection, OptionalExtension};
use serde::Serialize;
use serde_json::Value;

use super::error::CalendarSubscriptionError;
use crate::mutation::{Mutation, MutationOutput};

/// Typed `sync_health` enum mirroring the `CASE` expression in
/// [`list_calendar_subscriptions`]. Surfaces serialize it into their
/// IPC envelope unchanged.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CalendarSubscriptionSyncHealth {
    Disabled,
    Pending,
    Healthy,
    Stale,
    Failing,
}

impl TryFrom<&str> for CalendarSubscriptionSyncHealth {
    type Error = CalendarSubscriptionError;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "disabled" => Ok(Self::Disabled),
            "pending" => Ok(Self::Pending),
            "healthy" => Ok(Self::Healthy),
            "stale" => Ok(Self::Stale),
            "failing" => Ok(Self::Failing),
            _ => Err(CalendarSubscriptionError::Internal(format!(
                "unknown calendar subscription sync_health '{value}'"
            ))),
        }
    }
}

/// Read-side shape returned by [`list_calendar_subscriptions`]. Carries
/// both the canonical sync columns and the per-surface diagnostic
/// projection (`last_fetched_at`, `error_message`, `sync_health`) from
/// the `provider_scope_runtime_state` join. The legacy retry-backoff
/// fields remain in the serialized response as defaults for renderer
/// compatibility; the shared schema no longer persists them.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct CalendarSubscription {
    pub id: String,
    pub name: String,
    pub url: String,
    pub color: Option<String>,
    pub enabled: bool,
    pub last_fetched_at: Option<String>,
    pub error_message: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub next_retry_at: Option<String>,
    pub consecutive_failures: i64,
    pub last_retry_after_hint: Option<String>,
    pub sync_health: CalendarSubscriptionSyncHealth,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct RemoveCalendarSubscriptionResult {
    pub deleted: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ToggleCalendarSubscriptionResult {
    pub id: String,
    pub enabled: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct UpdateCalendarSubscriptionColorResult {
    pub id: String,
    pub color: Option<String>,
}

/// Read every `calendar_subscriptions` row joined with the corresponding
/// `provider_scope_runtime_state` snapshot. Pure read — surfaces call
/// this directly without going through [`Mutation`].
pub fn list_calendar_subscriptions(
    conn: &Connection,
) -> Result<Vec<CalendarSubscription>, CalendarSubscriptionError> {
    let mut stmt = conn
        .prepare_cached(
            "SELECT s.id, s.name, s.url, s.color, s.enabled,
                    f.last_refresh_success_at, f.last_error,
                    s.created_at, s.updated_at,
                    CASE
                        WHEN s.enabled = 0 THEN 'disabled'
                        WHEN f.availability_state IN ('permission_denied', 'authorization_error', 'fetch_error', 'parse_error')
                             OR f.last_refresh_result IN ('permission_denied', 'authorization_error', 'fetch_error', 'parse_error')
                        THEN 'failing'
                        WHEN f.provider_kind IS NULL OR f.last_refresh_success_at IS NULL THEN 'pending'
                        WHEN f.last_refresh_success_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-24 hours') THEN 'stale'
                        ELSE 'healthy'
                    END AS sync_health
             FROM calendar_subscriptions s
             LEFT JOIN provider_scope_runtime_state f
               ON f.provider_kind = 'ical_subscription' AND f.provider_scope = s.id
             ORDER BY s.created_at ASC",
        )
        .map_err(|e| CalendarSubscriptionError::Internal(e.to_string()))?;

    let rows: Vec<CalendarSubscription> = stmt
        .query_map([], |row| {
            let sync_health_raw: String = row.get(9)?;
            let sync_health = CalendarSubscriptionSyncHealth::try_from(sync_health_raw.as_str())
                .map_err(|error| {
                    rusqlite::Error::FromSqlConversionFailure(
                        9,
                        rusqlite::types::Type::Text,
                        Box::new(std::io::Error::new(
                            std::io::ErrorKind::InvalidData,
                            error.to_string(),
                        )),
                    )
                })?;
            Ok(CalendarSubscription {
                id: row.get(0)?,
                name: row.get(1)?,
                url: row.get(2)?,
                color: row.get(3)?,
                enabled: row.get(4)?,
                last_fetched_at: row.get(5)?,
                error_message: row.get(6)?,
                created_at: row.get(7)?,
                updated_at: row.get(8)?,
                next_retry_at: None,
                consecutive_failures: 0,
                last_retry_after_hint: None,
                sync_health,
            })
        })
        .map_err(|e| CalendarSubscriptionError::Internal(e.to_string()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| CalendarSubscriptionError::Internal(e.to_string()))?;

    Ok(rows)
}

// ── add ────────────────────────────────────────────────────────────

/// Mutation descriptor: INSERT a new `calendar_subscriptions` row with
/// `enabled = 1` and no fetch history. The id is minted at descriptor
/// construction so the caller can reference it before `apply` runs.
pub struct AddCalendarSubscriptionMutation {
    id: String,
    name: String,
    url: String,
    color: Option<String>,
}

impl AddCalendarSubscriptionMutation {
    /// Build a descriptor with a freshly-minted entity id. Inputs are
    /// trusted: the caller is responsible for URL safety / SSRF
    /// validation through [`super::validation`].
    #[must_use]
    pub fn new(name: String, url: String, color: Option<String>) -> Self {
        Self {
            id: lorvex_domain::new_entity_id_string(),
            name,
            url,
            color,
        }
    }

    #[must_use]
    pub fn id(&self) -> &str {
        &self.id
    }

    #[must_use]
    pub fn name(&self) -> &str {
        &self.name
    }

    #[must_use]
    pub fn url(&self) -> &str {
        &self.url
    }

    #[must_use]
    pub fn color(&self) -> Option<&str> {
        self.color.as_deref()
    }
}

impl Mutation for AddCalendarSubscriptionMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CALENDAR_SUBSCRIPTION
    }

    fn operation(&self) -> &'static str {
        OP_UPSERT
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let now = sync_timestamp_now();

        conn.execute(
            "INSERT INTO calendar_subscriptions (id, name, url, color, enabled, version, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, 1, ?5, ?6, ?6)",
            params![self.id, self.name, self.url, self.color, version, now],
        )?;

        let payload = lorvex_store::payload_loaders::calendar_subscription_payload(
            lorvex_store::payload_loaders::CalendarSubscriptionPayload {
                id: &self.id,
                name: &self.name,
                url: &self.url,
                color: self.color.as_deref(),
                enabled: true,
                created_at: &now,
                updated_at: &now,
                version: &version,
            },
        );
        Ok(MutationOutput::new(
            payload,
            format!("Added calendar subscription '{}'", self.name),
        ))
    }
}

/// Build the typed [`CalendarSubscription`] response for an
/// `add_calendar_subscription` write. Surfaces call this after their
/// finalizer runs so the IPC envelope carries the canonical
/// just-added shape (`Pending` sync_health, no fetch history, zero
/// failures).
#[must_use]
pub const fn add_response(
    id: String,
    name: String,
    url: String,
    color: Option<String>,
    created_at: String,
    updated_at: String,
) -> CalendarSubscription {
    CalendarSubscription {
        id,
        name,
        url,
        color,
        enabled: true,
        last_fetched_at: None,
        error_message: None,
        created_at,
        updated_at,
        next_retry_at: None,
        consecutive_failures: 0,
        last_retry_after_hint: None,
        sync_health: CalendarSubscriptionSyncHealth::Pending,
    }
}

// ── remove ─────────────────────────────────────────────────────────

/// Mutation descriptor: DELETE a `calendar_subscriptions` row + cascade
/// every cached provider event, task-event link, and runtime-state row
/// scoped to it. Provider data is canonical only inside the
/// subscription, so a delete is the one path that drops cached
/// provider rows (spec doc 19).
///
/// The `MutationOutput.after` carries the pre-delete sync payload so
/// the surface adapter can enqueue a `payload_delete` outbox envelope
/// with the same body peers expect to see in the tombstone wire shape.
/// When the targeted row does not exist, `after` is a placeholder
/// containing `{ "id": …, "deleted": false }` and the surface adapter
/// skips its outbox enqueue.
pub struct RemoveCalendarSubscriptionMutation {
    id: String,
}

impl RemoveCalendarSubscriptionMutation {
    #[must_use]
    pub const fn new(id: String) -> Self {
        Self { id }
    }

    #[must_use]
    pub fn id(&self) -> &str {
        &self.id
    }
}

impl Mutation for RemoveCalendarSubscriptionMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CALENDAR_SUBSCRIPTION
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, conn: &Connection) -> Result<Option<Value>, StoreError> {
        lorvex_store::payload_loaders::load_calendar_subscription_sync_payload(conn, &self.id)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let pre_delete_payload =
            lorvex_store::payload_loaders::load_calendar_subscription_sync_payload(conn, &self.id)?;

        lorvex_store::repositories::provider_repo::clear_provider_events_by_scope(
            conn,
            "ical_subscription",
            &self.id,
        )?;
        conn.execute(
            "DELETE FROM task_provider_event_links WHERE provider_kind = 'ical_subscription' AND provider_scope = ?1",
            params![self.id],
        )?;
        conn.execute(
            "DELETE FROM provider_scope_runtime_state WHERE provider_kind = 'ical_subscription' AND provider_scope = ?1",
            params![self.id],
        )?;

        let deleted = conn.execute(
            "DELETE FROM calendar_subscriptions WHERE id = ?1",
            params![self.id],
        )?;

        // mint a fresh HLC stamp for the tombstone envelope. The
        // pre-delete payload's version is the row's last LWW stamp, so
        // re-using it would coalesce against the prior upsert envelope
        // (incoming ≤ existing → outbox keeps the upsert). The
        // tombstone needs a strictly-greater stamp so peers replace the
        // synced row with the delete.
        let tombstone_version = hlc.next_version_string();
        let after = pre_delete_payload
            .map(|mut payload| {
                if let Some(obj) = payload.as_object_mut() {
                    obj.insert(
                        "version".to_string(),
                        Value::String(tombstone_version.clone()),
                    );
                }
                payload
            })
            .unwrap_or_else(|| serde_json::json!({ "id": self.id, "deleted": deleted > 0 }));
        let summary = if deleted > 0 {
            format!("Removed calendar subscription '{}'", self.id)
        } else {
            format!("No calendar subscription with id '{}'", self.id)
        };
        Ok(MutationOutput::new(after, summary))
    }
}

/// Did the row carried by a [`RemoveCalendarSubscriptionMutation`]
/// actually exist before the delete? Surface adapters consult this off
/// the post-apply payload to decide whether to enqueue a sync outbox
/// envelope.
#[must_use]
pub fn remove_payload_was_present(after: &Value) -> bool {
    // a real pre-delete payload carries the synced columns
    // (name + url + version); the placeholder produced when the row
    // was absent does not.
    after.get("version").is_some() && after.get("name").is_some()
}

// ── toggle ─────────────────────────────────────────────────────────

/// Mutation descriptor: flip the `enabled` flag on a subscription.
///
/// Tombstone behaviour: when no row matches, the mutation succeeds as
/// a row-affected=0 UPDATE. Matches the legacy IPC contract — the UI
/// drives an optimistic toggle and must be robust against a vanished
/// row.
pub struct ToggleCalendarSubscriptionMutation {
    id: String,
    enabled: bool,
}

impl ToggleCalendarSubscriptionMutation {
    #[must_use]
    pub const fn new(id: String, enabled: bool) -> Self {
        Self { id, enabled }
    }

    #[must_use]
    pub fn id(&self) -> &str {
        &self.id
    }

    #[must_use]
    pub const fn enabled(&self) -> bool {
        self.enabled
    }
}

impl Mutation for ToggleCalendarSubscriptionMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CALENDAR_SUBSCRIPTION
    }

    fn operation(&self) -> &'static str {
        OP_UPSERT
    }

    fn pre_snapshot(&self, conn: &Connection) -> Result<Option<Value>, StoreError> {
        lorvex_store::payload_loaders::load_calendar_subscription_sync_payload(conn, &self.id)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let now = sync_timestamp_now();
        let version = hlc.next_version_string();

        let updated = conn.execute(
            "UPDATE calendar_subscriptions SET enabled = ?1, updated_at = ?2, version = ?3 WHERE id = ?4",
            params![self.enabled as i64, now, version, self.id],
        )?;

        if updated == 0 {
            return Ok(MutationOutput::new(
                serde_json::json!({ "id": self.id, "enabled": self.enabled, "matched": false }),
                format!("No calendar subscription with id '{}'", self.id),
            ));
        }

        lorvex_store::repositories::provider_repo::update_provider_scope_state(
            conn,
            "ical_subscription",
            &self.id,
            lorvex_store::repositories::provider_repo::ProviderScopeTransition::Toggle {
                enabled: self.enabled,
            },
        )?;

        let after =
            lorvex_store::payload_loaders::load_calendar_subscription_sync_payload(conn, &self.id)?
                .ok_or_else(|| {
                    StoreError::Invariant(format!(
                        "calendar_subscription '{}' vanished after toggle UPDATE",
                        self.id
                    ))
                })?;
        Ok(MutationOutput::new(
            after,
            format!(
                "{} calendar subscription '{}'",
                if self.enabled { "Enabled" } else { "Disabled" },
                self.id
            ),
        ))
    }
}

/// Did the row exist when a [`ToggleCalendarSubscriptionMutation`] or
/// [`UpdateCalendarSubscriptionColorMutation`] applied? Surface
/// adapters consult this off the post-apply payload to decide whether
/// to enqueue a sync outbox envelope.
#[must_use]
pub fn upsert_payload_matched(after: &Value) -> bool {
    after.get("matched").and_then(Value::as_bool) != Some(false)
}

// ── color ──────────────────────────────────────────────────────────

/// Mutation descriptor: change the per-subscription color, cascading
/// the hex onto every cached `provider_calendar_events` row in the
/// scope so the timeline reflects the new color without waiting for a
/// re-sync.
pub struct UpdateCalendarSubscriptionColorMutation {
    id: String,
    color: Option<String>,
}

impl UpdateCalendarSubscriptionColorMutation {
    #[must_use]
    pub const fn new(id: String, color: Option<String>) -> Self {
        Self { id, color }
    }

    #[must_use]
    pub fn id(&self) -> &str {
        &self.id
    }

    #[must_use]
    pub fn color(&self) -> Option<&str> {
        self.color.as_deref()
    }
}

impl Mutation for UpdateCalendarSubscriptionColorMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CALENDAR_SUBSCRIPTION
    }

    fn operation(&self) -> &'static str {
        OP_UPSERT
    }

    fn pre_snapshot(&self, conn: &Connection) -> Result<Option<Value>, StoreError> {
        lorvex_store::payload_loaders::load_calendar_subscription_sync_payload(conn, &self.id)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let now = sync_timestamp_now();
        let version = hlc.next_version_string();

        let updated = conn.execute(
            "UPDATE calendar_subscriptions SET color = ?1, updated_at = ?2, version = ?3 WHERE id = ?4",
            params![self.color, now, version, self.id],
        )?;

        if updated == 0 {
            return Ok(MutationOutput::new(
                serde_json::json!({ "id": self.id, "color": self.color, "matched": false }),
                format!("No calendar subscription with id '{}'", self.id),
            ));
        }

        conn.execute(
            "UPDATE provider_calendar_events SET color = ?1 \
             WHERE provider_kind = 'ical_subscription' AND provider_scope = ?2",
            params![self.color, self.id],
        )?;

        let after =
            lorvex_store::payload_loaders::load_calendar_subscription_sync_payload(conn, &self.id)?
                .ok_or_else(|| {
                    StoreError::Invariant(format!(
                        "calendar_subscription '{}' vanished after color UPDATE",
                        self.id
                    ))
                })?;
        Ok(MutationOutput::new(
            after,
            format!("Updated calendar subscription '{}' color", self.id),
        ))
    }
}

/// Return `true` when a `calendar_subscriptions` row with this id
/// exists. Surfaces use this to short-circuit IPC envelope shape
/// (e.g. skip the outbox enqueue when a delete targeted a vanished row).
pub fn calendar_subscription_exists(
    conn: &Connection,
    id: &str,
) -> Result<bool, CalendarSubscriptionError> {
    let exists: Option<i64> = conn
        .query_row(
            "SELECT 1 FROM calendar_subscriptions WHERE id = ?1",
            params![id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| CalendarSubscriptionError::Internal(e.to_string()))?;
    Ok(exists.is_some())
}
