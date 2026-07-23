use super::tests_support::*;
use super::*;

mod classify_existing_sync_file_regression {
    use super::*;
    use super::{classify_existing_sync_file, ExistingSyncFileClassification};

    fn envelope(
        version: &str,
        entity_type: &str,
        entity_id: &str,
        device_id: &str,
    ) -> SyncEnvelope {
        SyncEnvelope {
            entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
                .expect("test entity_type must be a known EntityKind"),
            entity_id: entity_id.to_string(),
            operation: SyncOperation::Upsert,
            version: lorvex_domain::hlc::Hlc::parse(version).expect("test fixture HLC"),
            payload_schema_version: 1,
            payload: "{}".to_string(),
            device_id: device_id.to_string(),
        }
    }

    fn raw(env: &SyncEnvelope) -> String {
        serde_json::to_string(env).expect("serialize envelope")
    }

    #[test]
    fn match_when_full_quad_agrees() {
        let env = envelope(
            "0001711060000_0001_6465766963656131",
            "task",
            "t-1",
            "device-a",
        );
        let result = classify_existing_sync_file(&raw(&env), &env).unwrap();
        assert_eq!(result, ExistingSyncFileClassification::Match);
    }

    #[test]
    fn on_disk_older_when_existing_version_strictly_less() {
        let new = envelope(
            "0001711060099_0001_6465766963656131",
            "task",
            "t-1",
            "device-a",
        );
        let stale = envelope(
            "0001711060000_0001_6465766963656131",
            "task",
            "t-1",
            "device-a",
        );
        let result = classify_existing_sync_file(&raw(&stale), &new).unwrap();
        assert_eq!(result, ExistingSyncFileClassification::OnDiskOlder);
    }

    #[test]
    fn on_disk_newer_when_existing_version_strictly_greater() {
        let new = envelope(
            "0001711060099_0001_6465766963656131",
            "task",
            "t-1",
            "device-a",
        );
        let stale_local = envelope(
            "0001711060000_0001_6465766963656131",
            "task",
            "t-1",
            "device-a",
        );
        let result = classify_existing_sync_file(&raw(&new), &stale_local).unwrap();
        assert_eq!(result, ExistingSyncFileClassification::OnDiskNewer);
    }

    // typed `version: Hlc` rejects the legacy
    // `"v1"` placeholder fixtures at parse time. The mismatch
    // classifier compares quad fields (entity_type, entity_id,
    // device_id, version) byte-for-byte, so any canonical HLC the two
    // sides share is sufficient — pick a fixed canonical value and
    // reuse it across the four mismatch scenarios below.
    const FIXTURE_HLC: &str = "0001711060000_0001_6465766963656131";

    #[test]
    fn mismatch_when_entity_type_differs() {
        let local = envelope(FIXTURE_HLC, "task", "t-1", "device-a");
        let on_disk = envelope(FIXTURE_HLC, "list", "t-1", "device-a");
        let result = classify_existing_sync_file(&raw(&on_disk), &local).unwrap();
        assert_eq!(result, ExistingSyncFileClassification::Mismatch);
    }

    #[test]
    fn mismatch_when_entity_id_differs() {
        let local = envelope(FIXTURE_HLC, "task", "t-1", "device-a");
        let on_disk = envelope(FIXTURE_HLC, "task", "t-2", "device-a");
        let result = classify_existing_sync_file(&raw(&on_disk), &local).unwrap();
        assert_eq!(result, ExistingSyncFileClassification::Mismatch);
    }

    #[test]
    fn mismatch_when_device_id_differs() {
        let local = envelope(FIXTURE_HLC, "task", "t-1", "device-a");
        let on_disk = envelope(FIXTURE_HLC, "task", "t-1", "device-b");
        let result = classify_existing_sync_file(&raw(&on_disk), &local).unwrap();
        assert_eq!(result, ExistingSyncFileClassification::Mismatch);
    }

    #[test]
    fn malformed_existing_envelope_surfaces_serialization_error() {
        let env = envelope(FIXTURE_HLC, "task", "t-1", "device-a");
        let err = classify_existing_sync_file("{not valid json", &env)
            .expect_err("malformed JSON should fail to parse");
        match err {
            crate::error::AppError::Serialization(_) => {}
            other => panic!("expected Serialization, got {other:?}"),
        }
    }
}
