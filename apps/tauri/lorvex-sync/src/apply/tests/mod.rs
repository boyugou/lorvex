#![cfg(test)]
//! Sync-apply pipeline tests, extracted from apply/mod.rs.

use super::redirect::chase_redirect_chain;
use super::*;
use crate::envelope::{SyncEnvelope, SyncOperation};
use crate::test_db;
use crate::tombstone::create_tombstone;
use lorvex_domain::{hlc::HlcSurface, naming, version::PAYLOAD_SCHEMA_VERSION};
use lorvex_runtime::device_id_to_hlc_suffix;
use rusqlite::Connection;

mod apply_ts_capture;
mod audit;
mod child;
mod device_identity;
mod edge;
mod entity;
mod entity_focus_review;
mod issue_2827_2830;
mod issue_2964;
mod payload_shadow;
mod tombstone;
mod version;
mod version_concurrent;

pub(super) const LWW_V_OLD: &str = "1711234560000_0000_a1b2c3d4a1b2c3d4";
pub(super) const LWW_V_NEW: &str = "1711234569999_0000_a1b2c3d4a1b2c3d4";
pub(super) const MATRIX_V_A: &str = "1711234560000_0000_aaaaaaaaaaaaaaaa";
pub(super) const MATRIX_V_B: &str = "1711234569999_0000_aaaaaaaaaaaaaaaa";
pub(super) const DUMMY_UUID_A: &str = "01966a3f-7c8b-7d4e-8f3a-000000000101";
pub(super) const DUMMY_UUID_B: &str = "01966a3f-7c8b-7d4e-8f3a-000000000102";

pub(super) fn make_envelope(entity_type: &str, entity_id: &str, version: &str) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
            .expect("test entity_type must be a known EntityKind"),
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Upsert,
        // typed `version: Hlc` — non-canonical fixtures
        // now fail at construction (mirrors serde-deserialize).
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: make_payload_for_entity_type(entity_type),
        device_id: "remote-device".to_string(),
    }
}

pub(super) fn make_delete_envelope(
    entity_type: &str,
    entity_id: &str,
    version: &str,
) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
            .expect("test entity_type must be a known EntityKind"),
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Delete,
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: "{}".to_string(),
        device_id: "remote-device".to_string(),
    }
}

pub(super) fn make_payload_for_entity_type(entity_type: &str) -> String {
    match entity_type {
        naming::ENTITY_TASK => r#"{"title":"t","status":"open","defer_count":0,"created_at":"","updated_at":""}"#.to_string(),
        naming::ENTITY_LIST => r#"{"name":"l","created_at":"","updated_at":""}"#.to_string(),
        naming::ENTITY_HABIT => r#"{"name":"h","frequency_type":"daily","target_count":1,"archived":false,"created_at":"","updated_at":""}"#.to_string(),
        naming::ENTITY_TAG => r#"{"display_name":"tag","lookup_key":"tag","created_at":"","updated_at":""}"#.to_string(),
        naming::ENTITY_CALENDAR_EVENT => r#"{"title":"e","start_date":"2026-01-01","all_day":false,"event_type":"event","created_at":"","updated_at":""}"#.to_string(),
        naming::ENTITY_PREFERENCE => r#"{"value":"v","updated_at":""}"#.to_string(),
        naming::ENTITY_MEMORY => r#"{"content":"c","updated_at":""}"#.to_string(),
        naming::ENTITY_MEMORY_REVISION => r#"{"memory_key":"test-key","content":"c","operation":"upsert","actor":"ai","version":"1711234567890_0000_a1b2c3d4a1b2c3d4","created_at":""}"#.to_string(),
        naming::ENTITY_DAILY_REVIEW => r#"{"summary":"s","linked_task_ids":[],"linked_list_ids":[],"created_at":"","updated_at":""}"#.to_string(),
        naming::ENTITY_CURRENT_FOCUS => r#"{"task_ids":[],"created_at":"","updated_at":""}"#.to_string(),
        naming::ENTITY_FOCUS_SCHEDULE => r#"{"blocks":[],"created_at":"","updated_at":""}"#.to_string(),
        naming::ENTITY_CALENDAR_SUBSCRIPTION => r#"{"name":"n","url":"https://example.com","enabled":true,"created_at":"","updated_at":""}"#.to_string(),
        naming::ENTITY_TASK_REMINDER => format!(r#"{{"task_id":"{DUMMY_UUID_A}","reminder_at":"2026-01-01T09:00:00Z","created_at":"","updated_at":""}}"#),
        naming::ENTITY_TASK_CHECKLIST_ITEM => format!(r#"{{"task_id":"{DUMMY_UUID_A}","position":0,"text":"item","completed_at":null,"created_at":"","updated_at":""}}"#),
        naming::ENTITY_HABIT_REMINDER_POLICY => format!(r#"{{"habit_id":"{DUMMY_UUID_A}","reminder_time":"09:00","enabled":true,"created_at":"","updated_at":""}}"#),
        // Audit (post commit c0ea555bd): the trust-boundary
        // validator now rejects empty/whitespace-only required strings
        // on `ai_changelog` payloads, so the fixture supplies real
        // timestamps + non-empty fields.
        naming::ENTITY_AI_CHANGELOG => r#"{"timestamp":"2026-04-25T12:00:00.000Z","operation":"create","entity_type":"task","summary":"s","initiated_by":"ai","undo_token":null,"is_preview":false}"#.to_string(),
        _ => r"{}".to_string(),
    }
}

pub(super) fn suitable_entity_id(entity_type: &str) -> String {
    match entity_type {
        // Day-scoped entities need a date-like id.
        naming::ENTITY_DAILY_REVIEW
        | naming::ENTITY_CURRENT_FOCUS
        | naming::ENTITY_FOCUS_SCHEDULE => "2026-01-01".to_string(),
        // Preference/memory use key as id.
        naming::ENTITY_PREFERENCE => "timezone".to_string(),
        naming::ENTITY_MEMORY => "test-key".to_string(),
        _ => DUMMY_UUID_A.to_string(),
    }
}

pub(super) fn make_payload_for_edge_type(edge_type: &str) -> String {
    match edge_type {
        naming::EDGE_TASK_TAG => {
            format!(r#"{{"task_id":"{DUMMY_UUID_A}","tag_id":"{DUMMY_UUID_B}","created_at":""}}"#)
        }
        naming::EDGE_TASK_DEPENDENCY => {
            format!(
                r#"{{"task_id":"{DUMMY_UUID_A}","depends_on_task_id":"{DUMMY_UUID_B}","created_at":""}}"#
            )
        }
        naming::EDGE_TASK_CALENDAR_EVENT_LINK => {
            format!(
                r#"{{"task_id":"{DUMMY_UUID_A}","calendar_event_id":"{DUMMY_UUID_B}","created_at":"","updated_at":""}}"#
            )
        }
        // payload-vs-entity_id consistency check
        // requires `completed_date` to match the second half of the
        // composite entity_id used by `apply_all_known_edge_types`.
        naming::EDGE_HABIT_COMPLETION => {
            format!(
                r#"{{"habit_id":"{DUMMY_UUID_A}","value":1,"completed_date":"2026-01-01","created_at":"","updated_at":""}}"#
            )
        }
        _ => r"{}".to_string(),
    }
}
