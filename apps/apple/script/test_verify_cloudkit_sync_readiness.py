#!/usr/bin/env python3
from __future__ import annotations

import unittest

from verify_cloudkit_sync_readiness import (
    SYNC_NAMING,
    ckdb_lorvex_entity_fields,
    cloudkit_audit_retention_metadata_schema_failures,
    cloudkit_entity_coverage_failures,
    cloudkit_field_encryption_failures,
    cloudkit_sync_readiness_failures,
    cloudkit_zone_epoch_schema_failures,
    field_encryption_contract,
    swift_readiness_ids,
    syncable_kinds,
)


ENVELOPE_FIELD_SOURCE = """
    public static let entityType = "entity_type"
    public static let entityId = "entity_id"
    public static let operation = "operation"
    public static let version = "version"
    public static let payloadSchemaVersion = "payload_schema_version"
    public static let payload = "payload"
    public static let deviceId = "device_id"
    public static let encrypted = [
      entityId, entityType, operation, payload, deviceId, version, payloadSchemaVersion,
    ]
"""

# A client split with one plaintext wire field, for exercising the
# plaintext-direction drift lanes the production (all-encrypted) split can no
# longer reach.
MIXED_SPLIT_ENVELOPE_SOURCE = """
    public static let entityType = "entity_type"
    public static let entityId = "entity_id"
    public static let operation = "operation"
    public static let version = "version"
    public static let payloadSchemaVersion = "payload_schema_version"
    public static let payload = "payload"
    public static let deviceId = "device_id"
    public static let plaintext = [payloadSchemaVersion]
    public static let encrypted = [entityId, entityType, operation, payload, deviceId, version]
"""

CKDB_SOURCE = """
    RECORD TYPE LorvexEntity (
        "___recordID"   REFERENCE QUERYABLE,
        entity_type             ENCRYPTED STRING,
        entity_id               ENCRYPTED STRING,
        operation               ENCRYPTED STRING,
        version                 ENCRYPTED STRING,
        payload_schema_version  ENCRYPTED STRING,
        payload                 ENCRYPTED STRING,
        device_id               ENCRYPTED STRING,
        GRANT WRITE TO "_creator"
    );
"""


ZONE_EPOCH_SOURCE = """
  static let recordType = "LorvexZoneEpoch"
  static let recordName = "lorvex-zone-epoch"
  static let protocolVersionField = "protocol_version"
  static let epochField = "epoch"
  static let stateField = "state"
  static let activeEpochField = "active_epoch"
  static let generationIDField = "generation_id"
  static let activeZoneField = "active_zone"
  static let readyWitnessField = "ready_witness"
  static let candidateGenerationIDField = "candidate_generation_id"
  static let candidateZoneField = "candidate_zone"
  static let rebuildIdentifierField = "rebuild_id"
  static let rebuildOwnerField = "rebuild_owner"
  static let rebuildPhaseField = "rebuild_phase"
  static let leaseActivityAtField = "lease_activity_at"
  static let retiredZonesField = "retired_zones_json"
  static let tombstoneCompactionCutoffField = "tombstone_compaction_cutoff"
"""

CKDB_WITH_EPOCH = (
    CKDB_SOURCE
    + '''
    RECORD TYPE LorvexZoneEpoch (
        "___recordID"   REFERENCE QUERYABLE,
        protocol_version           INT64,
        epoch                      INT64,
        state                      STRING,
        active_epoch               INT64,
        generation_id              STRING,
        active_zone                STRING,
        ready_witness              STRING,
        candidate_generation_id    STRING,
        candidate_zone             STRING,
        rebuild_id                 STRING,
        rebuild_owner              STRING,
        rebuild_phase              STRING,
        lease_activity_at          STRING,
        retired_zones_json         STRING,
        tombstone_compaction_cutoff STRING,
        GRANT WRITE TO "_creator"
    );
'''
)


AUDIT_RETENTION_METADATA_SOURCE = """
  static let recordType = "LorvexAuditRetentionMetadata"
  static let protocolVersionField = "protocol_version"
  static let generationEpochField = "generation_epoch"
  static let generationIDField = "generation_id"
  static let frontierEpochField = "frontier_epoch"
  static let cutoffTimestampField = "cutoff_timestamp"
  static let cutoffEntityIDField = "cutoff_entity_id"
  static let policyField = "policy"
  static let policyVersionField = "policy_version"
  static let policyAuthorizedEpochField = "policy_authorized_epoch"
  static let encryptedFields = [
    protocolVersionField, generationEpochField, generationIDField,
    frontierEpochField, cutoffTimestampField, cutoffEntityIDField,
    policyField, policyVersionField, policyAuthorizedEpochField,
  ]
  record.encryptedValues[protocolVersionField] = value
  record.encryptedValues[generationEpochField] = value
  record.encryptedValues[generationIDField] = value
  record.encryptedValues[frontierEpochField] = value
  record.encryptedValues[cutoffTimestampField] = value
  record.encryptedValues[cutoffEntityIDField] = value
  record.encryptedValues[policyField] = value
  record.encryptedValues[policyVersionField] = value
  record.encryptedValues[policyAuthorizedEpochField] = value
"""

CKDB_WITH_AUDIT_RETENTION = (
    CKDB_SOURCE
    + """
    RECORD TYPE LorvexAuditRetentionMetadata (
        "___recordID"          REFERENCE QUERYABLE,
        protocol_version        ENCRYPTED INT64,
        generation_epoch        ENCRYPTED INT64,
        generation_id           ENCRYPTED STRING,
        frontier_epoch          ENCRYPTED INT64,
        cutoff_timestamp        ENCRYPTED STRING,
        cutoff_entity_id        ENCRYPTED STRING,
        policy                  ENCRYPTED STRING,
        policy_version          ENCRYPTED STRING,
        policy_authorized_epoch ENCRYPTED INT64,
        GRANT WRITE TO "_creator"
    );
"""
)


SWIFT_SOURCE = """
Capability(
  id: "export",
  title: "Outbound record export",
  status: .ready,
  detail: "Projects tasks."
),
Capability(
  id: "subscription",
  title: "Private database subscription",
  status: .ready,
  detail: "Registers pushes."
),
Capability(
  id: "remote-refresh",
  title: "Remote-change refresh",
  status: .ready,
  detail: "Refreshes."
),
Capability(
  id: "inbound-apply",
  title: "Inbound record application",
  status: .ready,
  detail: "Merged."
),
Capability(
  id: "change-token",
  title: "Change-token checkpointing",
  status: .ready,
  detail: "Checkpointed."
),
"""


# --- Entity-coverage fixtures ------------------------------------------------
#
# A miniature but shape-faithful authority: naming constants, the EntityKind
# enum, a local-only kind kept OUT of allSyncableTypes, an edge referenced via
# EdgeName (whose constant lives in another Swift file, so it must resolve
# through the enum-case map), and an inbound-only audit kind.

NAMING_SOURCE = """
public enum EntityName {
  public static let task = "task"
  public static let list = "list"
  public static let calendarSeriesCutover = "calendar_series_cutover"
  public static let dailyReview = "daily_review"
  public static let aiChangelog = "ai_changelog"
  public static let entityRedirect = "entity_redirect"
  public static let deviceState = "device_state"
}

public enum EntityKind: String, Sendable, Hashable, Codable, CaseIterable {
  case task = "task"
  case list = "list"
  case calendarSeriesCutover = "calendar_series_cutover"
  case dailyReview = "daily_review"
  case aiChangelog = "ai_changelog"
  case entityRedirect = "entity_redirect"
  case taskTag = "task_tag"
  case deviceState = "device_state"

  public static let allSyncableTypes: [String] = [
    EntityName.task,
    EntityName.list,
    EntityName.calendarSeriesCutover,
    EntityName.dailyReview,
    EntityName.aiChangelog,
    EntityName.entityRedirect,
    EdgeName.taskTag,
  ]
}
"""

APPLY_DISPATCH_SOURCE = """
extension EntityApplierRegistry {
  public static func defaultEntityAppliers() -> [any EntityApplier] {
    [
      TaskApplier(), ListApplier(), CalendarSeriesCutoverApplier(), TaskTagApplier(),
      DailyReviewApplier(), ChangelogApplier(),
    ]
  }
}
"""

SYNC_APPLIER_SOURCES = {
    "ApplyTask.swift": """
public struct TaskApplier: EntityApplier {
  public var handledEntityTypes: [String] { [EntityKind.task.asString] }
}
""",
    "ApplyList.swift": """
public struct ListApplier: EntityApplier {
  public var handledEntityTypes: [String] { [EntityName.list] }
}
""",
    "ApplyCalendarSeriesCutover.swift": """
public struct CalendarSeriesCutoverApplier: EntityApplier {
  public var handledEntityTypes: [String] { [EntityName.calendarSeriesCutover] }
}
""",
    "ApplyEdge.swift": """
public struct TaskTagApplier: EntityApplier {
  public var handledEntityTypes: [String] { [EntityKind.taskTag.asString] }
}
""",
    "ApplyDayScoped.swift": """
public struct DailyReviewApplier: EntityApplier {
  public var handledEntityTypes: [String] { [EntityName.dailyReview] }
}
""",
    "ApplyChangelog.swift": """
public struct ChangelogApplier: EntityApplier {
  public var handledEntityTypes: [String] { [EntityName.aiChangelog] }
}
""",
    "Apply.swift": """
if envelope.entityType == .entityRedirect {
  return try EntityRedirect.applyInbound(
    db, registry: registry, envelope: envelope, applyTs: applyTs)
}
""",
    "EntityRedirect.swift": """
public enum EntityRedirect {
  static func upsertAndEnqueue(
    _ db: Database, sourceType: EntityKind, sourceId: String, targetId: String,
    version: String, createdAt: String, deviceId: String
  ) throws -> Record {
    let outcome = try upsertJoined(
      db, sourceType: sourceType, sourceId: sourceId, targetId: targetId,
      version: version, createdAt: createdAt)
    try enqueue(db, record: outcome.record, deviceId: deviceId)
    return outcome.record
  }

  static func applyInbound(
    _ db: Database, registry: EntityApplierRegistry, envelope: SyncEnvelope, applyTs: String
  ) throws -> ApplyResult {
    guard envelope.operation == .upsert else { throw TestError.invalid }
    return .applied
  }

  static func makeEnvelope(record: Record, deviceId: String) throws -> SyncEnvelope {
    SyncEnvelope(
      entityType: .entityRedirect, entityId: record.sourceId,
      operation: .upsert, version: record.version, payload: "{}", deviceId: deviceId)
  }
}
""",
}

SERVICE_SOURCES = {
    "SwiftLorvexCoreService+Tasks.swift": """
try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)
try self.enqueueDelete(
  db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id, payload: payload)
""",
    "SwiftLorvexCoreService+Tags.swift": """
try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .list, entityId: id)
try self.enqueueDelete(db, hlc: hlc, deviceId: deviceId, kind: .list, entityId: id, payload: p)
""",
    "SwiftLorvexCoreService+Review.swift": """
try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .dailyReview, entityId: date)
""",
    "SwiftLorvexCoreService+CalendarCutovers.swift": """
try self.enqueueUpsert(
  db, hlc: hlc, deviceId: deviceId, kind: .calendarSeriesCutover, entityId: id)
""",
    "SwiftLorvexCoreService+OutboxFlush.swift": """
try enqueueEdgeUpsert(
  db, hlc: hlc, deviceId: deviceId, kind: .taskTag, entityId: edgeId, payload: payload)
""",
    "SwiftLorvexCoreService+OutboxDeleteCascade.swift": """
try enqueueDelete(db, hlc: hlc, deviceId: deviceId, kind: .taskTag, entityId: edgeId, payload: p)
""",
}

# The fixture's intentional directionality gaps, mirroring the production
# shape: the audit stream is inbound-only; the day-keyed review kind has no
# local delete operation to emit.
FIXTURE_EXCEPTIONS = {
    "ai_changelog": {
        "outbound_upsert": "inbound-only audit stream",
        "outbound_delete": "append-only audit stream",
    },
    "daily_review": {"outbound_delete": "add/amend-only; no local delete op"},
    "calendar_series_cutover": {
        "outbound_delete": "absorbing remove-wins boundary is upsert-only"
    },
    "entity_redirect": {
        "outbound_delete": "permanent absorbing alias is upsert-only"
    },
}

# Every kind the live authority is known to carry today. A subset assertion:
# new kinds may be added freely (the gate auto-covers them); a REMOVAL from
# this set must be a conscious decision that updates this pin.
KNOWN_LIVE_SYNCABLE_WIRES = {
    "task",
    "list",
    "habit",
    "tag",
    "calendar_event",
    "calendar_series_cutover",
    "preference",
    "memory",
    "daily_review",
    "current_focus",
    "focus_schedule",
    "task_reminder",
    "task_checklist_item",
    "habit_reminder_policy",
    "ai_changelog",
    "entity_redirect",
    "task_tag",
    "task_dependency",
    "task_calendar_event_link",
    "habit_completion",
}


def coverage_failures(
    naming: str = NAMING_SOURCE,
    dispatch: str = APPLY_DISPATCH_SOURCE,
    sync_sources: dict[str, str] = SYNC_APPLIER_SOURCES,
    service_sources: dict[str, str] = SERVICE_SOURCES,
    exceptions: dict[str, dict[str, str]] = FIXTURE_EXCEPTIONS,
) -> list[str]:
    return cloudkit_entity_coverage_failures(
        naming, dispatch, sync_sources, service_sources, exceptions=exceptions
    )


class VerifyCloudKitSyncReadinessTests(unittest.TestCase):
    def test_swift_readiness_ids_maps_swift_ids_to_release_ids(self) -> None:
        self.assertEqual(
            swift_readiness_ids(SWIFT_SOURCE),
            {
                "ready": [
                    "outbound_record_export",
                    "private_database_subscription",
                    "remote_change_refresh",
                    "inbound_record_application",
                    "change_token_checkpointing",
                ],
                "pending": [],
            },
        )

    def test_cloudkit_sync_readiness_failures_accepts_matching_contract(self) -> None:
        self.assertEqual(cloudkit_sync_readiness_failures(SWIFT_SOURCE), [])

    def test_cloudkit_sync_readiness_failures_rejects_status_drift(self) -> None:
        drifted = SWIFT_SOURCE.replace('id: "inbound-apply"', 'id: "inbound-apply"').replace(
            "status: .ready,\n  detail: \"Merged.\"",
            "status: .pending,\n  detail: \"Merged.\"",
            1,
        )

        failures = cloudkit_sync_readiness_failures(drifted)

        self.assertTrue(any("ready mismatch" in failure for failure in failures))
        self.assertTrue(any("pending mismatch" in failure for failure in failures))

    def test_cloudkit_sync_readiness_failures_rejects_unknown_swift_id(self) -> None:
        source = SWIFT_SOURCE + """
        Capability(
          id: "server-token",
          title: "Server token",
          status: .pending,
          detail: "New unchecked capability."
        ),
        """

        self.assertEqual(
            cloudkit_sync_readiness_failures(source),
            ["CloudKit readiness declares unknown Swift capability id(s): ['server-token']"],
        )

    # --- Syncable-kind inventory derivation ----------------------------------

    def test_syncable_kinds_derived_from_all_syncable_types(self) -> None:
        kinds, failures = syncable_kinds(NAMING_SOURCE)

        self.assertEqual(failures, [])
        self.assertEqual(
            kinds,
            [
                ("task", "task"),
                ("list", "list"),
                ("calendarSeriesCutover", "calendar_series_cutover"),
                ("dailyReview", "daily_review"),
                ("aiChangelog", "ai_changelog"),
                ("entityRedirect", "entity_redirect"),
                ("taskTag", "task_tag"),
            ],
        )
        # Local-only kinds stay out of scope because the derivation reads
        # allSyncableTypes, not allCases.
        self.assertNotIn("device_state", {wire for _, wire in kinds})

    def test_syncable_kinds_fails_when_authority_block_is_missing(self) -> None:
        kinds, failures = syncable_kinds("public enum EntityKind { case task = \"task\" }")

        self.assertEqual(kinds, [])
        self.assertTrue(any("allSyncableTypes" in failure for failure in failures))

    def test_syncable_kinds_fails_when_member_has_no_entity_kind_case(self) -> None:
        # A wire constant referenced by the authority without a matching
        # EntityKind case is vocabulary drift, not a silent skip.
        drifted = NAMING_SOURCE.replace(
            'public static let deviceState = "device_state"',
            'public static let widgetState = "widget_state"\n'
            '  public static let deviceState = "device_state"',
        ).replace(
            "    EdgeName.taskTag,",
            "    EdgeName.taskTag,\n    EntityName.widgetState,",
        )

        kinds, failures = syncable_kinds(drifted)

        self.assertIn(("taskTag", "task_tag"), kinds)
        self.assertTrue(
            any("widget_state" in failure and "EntityKind case" in failure for failure in failures),
            failures,
        )

    def test_live_authority_inventory_is_complete_and_excludes_local_only(self) -> None:
        kinds, failures = syncable_kinds(SYNC_NAMING.read_text(encoding="utf-8"))

        self.assertEqual(failures, [])
        wires = {wire for _, wire in kinds}
        self.assertLessEqual(KNOWN_LIVE_SYNCABLE_WIRES, wires)
        self.assertNotIn("device_state", wires)
        self.assertNotIn("import_session", wires)

    # --- Full-inventory entity coverage ---------------------------------------

    def test_coverage_accepts_fully_covered_inventory(self) -> None:
        self.assertEqual(coverage_failures(), [])

    def test_coverage_fails_for_new_authority_kind_without_readiness(self) -> None:
        # DRIFT GUARD: adding a syncable kind to the authority without wiring
        # apply/outbox coverage must fail the gate — coverage is derived from
        # allSyncableTypes, never from a hand-maintained list.
        drifted_naming = NAMING_SOURCE.replace(
            'case deviceState = "device_state"',
            'case widgetState = "widget_state"\n  case deviceState = "device_state"',
        ).replace(
            "    EdgeName.taskTag,",
            "    EdgeName.taskTag,\n    EntityName.widgetState,",
        )

        failures = coverage_failures(naming=drifted_naming)

        self.assertEqual(
            failures,
            [
                "CloudKit entity coverage missing inbound applier for widget_state",
                "CloudKit entity coverage missing outbound enqueue for widget_state",
                "CloudKit entity coverage missing delete enqueue for widget_state",
            ],
        )

    def test_coverage_fails_when_registered_applier_is_removed(self) -> None:
        # The applier struct still exists in LorvexSync, but is no longer
        # registered in defaultEntityAppliers() — dispatch would throw
        # unknownEntityType, so the gate must fail.
        dispatch = APPLY_DISPATCH_SOURCE.replace("DailyReviewApplier(), ", "")

        failures = coverage_failures(dispatch=dispatch)

        self.assertEqual(
            failures,
            ["CloudKit entity coverage missing inbound applier for daily_review"],
        )

    def test_coverage_fails_when_outbound_upsert_enqueue_is_missing(self) -> None:
        services = dict(SERVICE_SOURCES)
        services["SwiftLorvexCoreService+OutboxFlush.swift"] = ""

        failures = coverage_failures(service_sources=services)

        self.assertEqual(
            failures,
            ["CloudKit entity coverage missing outbound enqueue for task_tag"],
        )

    def test_coverage_fails_when_delete_enqueue_is_missing(self) -> None:
        services = dict(SERVICE_SOURCES)
        services["SwiftLorvexCoreService+Tasks.swift"] = (
            "try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)"
        )

        failures = coverage_failures(service_sources=services)

        self.assertEqual(
            failures,
            ["CloudKit entity coverage missing delete enqueue for task"],
        )

    def test_redirect_requires_dedicated_inbound_dispatch(self) -> None:
        sync_sources = dict(SYNC_APPLIER_SOURCES)
        sync_sources["Apply.swift"] = ""

        failures = coverage_failures(sync_sources=sync_sources)

        self.assertEqual(
            failures,
            ["CloudKit entity coverage missing inbound applier for entity_redirect"],
        )

    def test_redirect_requires_dedicated_outbound_upsert_producer(self) -> None:
        sync_sources = dict(SYNC_APPLIER_SOURCES)
        sync_sources["EntityRedirect.swift"] = sync_sources[
            "EntityRedirect.swift"
        ].replace("try enqueue(db, record: outcome.record, deviceId: deviceId)", "")

        failures = coverage_failures(sync_sources=sync_sources)

        self.assertEqual(
            failures,
            ["CloudKit entity coverage missing outbound enqueue for entity_redirect"],
        )

    def test_redirect_upsert_only_delete_lane_requires_explicit_exception(self) -> None:
        exceptions = dict(FIXTURE_EXCEPTIONS)
        exceptions.pop("entity_redirect")

        failures = coverage_failures(exceptions=exceptions)

        self.assertEqual(
            failures,
            ["CloudKit entity coverage missing delete enqueue for entity_redirect"],
        )

    def test_cutover_upsert_only_delete_lane_requires_explicit_exception(self) -> None:
        exceptions = dict(FIXTURE_EXCEPTIONS)
        exceptions.pop("calendar_series_cutover")

        failures = coverage_failures(exceptions=exceptions)

        self.assertEqual(
            failures,
            [
                "CloudKit entity coverage missing delete enqueue for "
                "calendar_series_cutover"
            ],
        )

    # --- Directionality exceptions --------------------------------------------

    def test_exception_without_allow_entry_fails(self) -> None:
        # Dropping the documented allow-entry re-arms the checks it gated:
        # exceptions are explicit, never implied by omission.
        exceptions = {
            "ai_changelog": FIXTURE_EXCEPTIONS["ai_changelog"],
            "calendar_series_cutover": FIXTURE_EXCEPTIONS["calendar_series_cutover"],
            "entity_redirect": FIXTURE_EXCEPTIONS["entity_redirect"],
        }

        failures = coverage_failures(exceptions=exceptions)

        self.assertEqual(
            failures,
            ["CloudKit entity coverage missing delete enqueue for daily_review"],
        )

    def test_stale_exception_fails_when_lane_gains_coverage(self) -> None:
        services = dict(SERVICE_SOURCES)
        services["SwiftLorvexCoreService+Review.swift"] = """
try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .dailyReview, entityId: date)
try self.enqueueDelete(db, hlc: hlc, deviceId: deviceId, kind: .dailyReview, entityId: date, payload: p)
"""

        failures = coverage_failures(service_sources=services)

        self.assertEqual(len(failures), 1)
        self.assertIn("stale directionality exception", failures[0])
        self.assertIn("daily_review", failures[0])
        self.assertIn("outbound_delete", failures[0])

    def test_exception_for_unknown_kind_fails(self) -> None:
        exceptions = dict(FIXTURE_EXCEPTIONS)
        exceptions["widget_state"] = {"outbound_delete": "does not exist"}

        failures = coverage_failures(exceptions=exceptions)

        self.assertEqual(len(failures), 1)
        self.assertIn("unknown syncable kind", failures[0])
        self.assertIn("widget_state", failures[0])

    def test_exception_with_unknown_property_fails(self) -> None:
        # Inbound apply is never exceptable: allSyncableTypes IS the inbound
        # accept set, so only the two outbound lanes may carry allow-entries.
        exceptions = dict(FIXTURE_EXCEPTIONS)
        exceptions["daily_review"] = {"inbound_apply": "nope"}

        failures = coverage_failures(exceptions=exceptions)

        self.assertTrue(any("unknown property 'inbound_apply'" in f for f in failures), failures)

    # --- Field encryption contract ---------------------------------------------

    def test_field_encryption_contract_resolves_wire_names(self) -> None:
        plaintext, encrypted = field_encryption_contract(ENVELOPE_FIELD_SOURCE)
        # The client encrypts every wire field, so there is no `Field.plaintext`
        # declaration — the absent array resolves to an empty list, not a parse
        # failure.
        self.assertEqual(plaintext, [])
        self.assertEqual(
            encrypted,
            [
                "entity_id",
                "entity_type",
                "operation",
                "payload",
                "device_id",
                "version",
                "payload_schema_version",
            ],
        )

    def test_field_encryption_contract_missing_encrypted_array_is_parse_failure(self) -> None:
        plaintext, encrypted = field_encryption_contract("public static let payload = \"payload\"")
        # An absent plaintext array is the expected all-encrypted shape (`[]`);
        # only an absent `encrypted` array is a genuine parse failure.
        self.assertEqual(plaintext, [])
        self.assertIsNone(encrypted)

    def test_ckdb_lorvex_entity_fields_flags_encryption_and_skips_system(self) -> None:
        fields = ckdb_lorvex_entity_fields(CKDB_SOURCE)
        # System `___` columns and GRANT clauses are excluded.
        self.assertEqual(
            fields,
            {
                "entity_type": True,
                "entity_id": True,
                "operation": True,
                "version": True,
                "payload_schema_version": True,
                "payload": True,
                "device_id": True,
            },
        )

    def test_field_encryption_failures_accepts_matching_contract(self) -> None:
        self.assertEqual(
            cloudkit_field_encryption_failures(ENVELOPE_FIELD_SOURCE, CKDB_SOURCE), []
        )

    def test_field_encryption_failures_rejects_missing_contract_arrays(self) -> None:
        failures = cloudkit_field_encryption_failures(
            "public static let payload = \"payload\"", CKDB_SOURCE
        )
        self.assertEqual(len(failures), 1)
        self.assertIn("could not parse CloudSyncEnvelopeRecord.Field", failures[0])

    def test_field_encryption_failures_rejects_plaintext_declared_encrypted_field(self) -> None:
        # entity_id is routing metadata and may be a user-controlled natural key
        # for some kinds; if the template declares it plaintext while the client
        # encrypts it, every push to a fresh container fails.
        drifted = CKDB_SOURCE.replace(
            "entity_id               ENCRYPTED STRING", "entity_id               STRING"
        )
        failures = cloudkit_field_encryption_failures(ENVELOPE_FIELD_SOURCE, drifted)
        self.assertEqual(
            failures,
            [
                "schema.ckdb field 'entity_id' is declared plaintext but the client writes it "
                "via encryptedValues — declare it ENCRYPTED"
            ],
        )

    def test_field_encryption_failures_rejects_encrypted_declared_plaintext_field(self) -> None:
        # A client split carrying a plaintext field must find that field
        # declared plaintext in the template, not ENCRYPTED.
        failures = cloudkit_field_encryption_failures(MIXED_SPLIT_ENVELOPE_SOURCE, CKDB_SOURCE)
        self.assertEqual(
            failures,
            [
                "schema.ckdb field 'payload_schema_version' is declared ENCRYPTED but the "
                "client writes it in the clear — declare it plaintext"
            ],
        )

    def test_zone_epoch_schema_accepts_declared_int64_record_type(self) -> None:
        self.assertEqual(
            cloudkit_zone_epoch_schema_failures(ZONE_EPOCH_SOURCE, CKDB_WITH_EPOCH), []
        )

    def test_audit_retention_schema_accepts_complete_encrypted_shape(self) -> None:
        self.assertEqual(
            cloudkit_audit_retention_metadata_schema_failures(
                AUDIT_RETENTION_METADATA_SOURCE,
                CKDB_WITH_AUDIT_RETENTION,
            ),
            [],
        )

    def test_audit_retention_schema_rejects_plaintext_policy(self) -> None:
        drifted = CKDB_WITH_AUDIT_RETENTION.replace(
            "policy                  ENCRYPTED STRING",
            "policy                  STRING",
        )
        failures = cloudkit_audit_retention_metadata_schema_failures(
            AUDIT_RETENTION_METADATA_SOURCE,
            drifted,
        )
        self.assertTrue(any("policy is plaintext" in failure for failure in failures), failures)

    def test_zone_epoch_schema_fails_when_record_type_absent(self) -> None:
        # The exact production gap: the runtime saves LorvexZoneEpoch but the
        # template never declared it, so production CloudKit would reject the save.
        failures = cloudkit_zone_epoch_schema_failures(ZONE_EPOCH_SOURCE, CKDB_SOURCE)
        self.assertEqual(len(failures), 1)
        self.assertIn("missing RECORD TYPE LorvexZoneEpoch", failures[0])

    def test_zone_epoch_schema_fails_when_epoch_is_encrypted(self) -> None:
        encrypted = CKDB_WITH_EPOCH.replace(
            "epoch                      INT64",
            "epoch                      ENCRYPTED INT64",
        )
        failures = cloudkit_zone_epoch_schema_failures(ZONE_EPOCH_SOURCE, encrypted)
        self.assertEqual(len(failures), 1)
        self.assertIn("declared ENCRYPTED", failures[0])

    def test_zone_epoch_schema_fails_on_wrong_field_type(self) -> None:
        wrong = CKDB_WITH_EPOCH.replace(
            "epoch                      INT64",
            "epoch                      STRING",
        )
        failures = cloudkit_zone_epoch_schema_failures(ZONE_EPOCH_SOURCE, wrong)
        self.assertEqual(len(failures), 1)
        self.assertIn("must be INT64", failures[0])

    def test_zone_epoch_schema_fails_when_readiness_field_is_missing(self) -> None:
        missing = CKDB_WITH_EPOCH.replace("        state                      STRING,\n", "")
        failures = cloudkit_zone_epoch_schema_failures(ZONE_EPOCH_SOURCE, missing)
        self.assertEqual(len(failures), 1)
        self.assertIn("missing field 'state'", failures[0])

    def test_zone_epoch_schema_fails_when_lease_field_is_encrypted(self) -> None:
        encrypted = CKDB_WITH_EPOCH.replace(
            "rebuild_id                 STRING",
            "rebuild_id                 ENCRYPTED STRING",
        )
        failures = cloudkit_zone_epoch_schema_failures(ZONE_EPOCH_SOURCE, encrypted)
        self.assertEqual(len(failures), 1)
        self.assertIn("rebuild_id is declared ENCRYPTED", failures[0])

    def test_field_encryption_failures_rejects_unclassified_ckdb_field(self) -> None:
        # A template field the client neither encrypts nor writes plaintext is
        # drift: the client would never populate it.
        drifted = CKDB_SOURCE.replace(
            'GRANT WRITE TO "_creator"',
            'updated_at              STRING QUERYABLE SORTABLE,\n        GRANT WRITE TO "_creator"',
        )
        failures = cloudkit_field_encryption_failures(ENVELOPE_FIELD_SOURCE, drifted)
        self.assertEqual(
            failures,
            [
                "schema.ckdb LorvexEntity field 'updated_at' is not classified in "
                "CloudSyncEnvelopeRecord.Field.encrypted"
            ],
        )


if __name__ == "__main__":
    unittest.main()
