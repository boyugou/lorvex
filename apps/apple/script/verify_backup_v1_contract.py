#!/usr/bin/env python3
"""Pin the version-1 Apple backup wire contract.

Version 1 is the first public backup wire shape, not an alias for whichever
export DTOs the current app happens to use. The v1 archive owns self-contained
primitive wire DTOs, a closed JSON/ZIP inventory, native-graph-v1 semantics,
explicit adapters, and both production encoder/decoder paths. This gate pins
the frozen sources and every committed v1 fixture while structurally requiring
the mutable version adapter, so an export change either edits v1 in place
(pre-launch only) or adds a v2 branch — never silently reinterprets v1.

Like the schema checksum and sync-payload gates, this contract follows the
``launched`` sentinel in ``schema/migration_policy.json``:

* Pre-launch (``launched: false``): no shipped build has ever produced a v1
  archive, so the wire is freely editable in place. After an intentional wire
  edit, run the Swift backup suites (they print the actual golden digests on
  mismatch), paste the three digests into ``BackupV1GoldenFixture.swift``, and
  re-run this script with ``--seed`` to regenerate the lock. The Swift tests
  remain the authority for the encoder digests; the lock is the drift tripwire.
* Post-launch (``launched: true``): real archives exist. ``--seed`` refuses to
  run, every v1 hash is immutable, and a wire change must introduce a new
  versioned DTO/decoder (v2) instead of editing v1.
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path


APPLE_ROOT = Path(__file__).resolve().parents[1]
LOCK_PATH = APPLE_ROOT / "script" / "backup_v1_contract.lock"
POLICY_PATH = APPLE_ROOT.parents[1] / "schema" / "migration_policy.json"
FIXTURE_PATH = APPLE_ROOT / "Tests/LorvexAppleTests/BackupV1GoldenFixture.swift"


def is_launched() -> bool:
    """Read the repo-wide launch sentinel; missing/unreadable means launched.

    Failing toward the strict regime keeps the gate meaningful even if the
    policy file is absent in a partial checkout.
    """
    try:
        policy = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return True
    return bool(policy.get("launched", True))

REQUIRED_FROZEN_FILES = {
    "Sources/LorvexCore/Support/BackupV1Archive.swift",
    "Sources/LorvexCore/Support/BackupV1Contract.swift",
    "Sources/LorvexCore/Support/BackupV1NativeTaskGraphSemantics.swift",
    "Sources/LorvexCore/Support/BackupV1NativeTaskWire.swift",
    "Sources/LorvexCore/Support/BackupV1PayloadPreflight.swift",
    "Sources/LorvexCore/Support/BackupV1PortableWire.swift",
    "Sources/LorvexCore/Support/BackupV1RecurrenceSemantics.swift",
    "Sources/LorvexCore/Support/BackupV1SingleFileInventory.swift",
    "Sources/LorvexCore/Support/BackupV1TaskProjectionConsistency.swift",
    "Sources/LorvexCore/Support/BackupV1Wire.swift",
    "Sources/LorvexCore/Support/NativeTaskGraphValidation.swift",
    "Sources/LorvexCore/Support/NativeTaskGraphV1Validator.swift",
    "Tests/Fixtures/BackupFormat/v1-single-file.json",
    "Tests/Fixtures/BackupFormat/v1-zip-lists.json",
    "Tests/Fixtures/BackupFormat/v1-zip-manifest.json",
    "Tests/Fixtures/BackupFormat/v1-zip-tasks.json",
    "Tests/LorvexAppleTests/BackupV1GoldenFixture.swift",
    "core/Sources/LorvexDomain/CanonicalJSON.swift",
    "core/Sources/LorvexDomain/Hlc.swift",
    "core/Sources/LorvexDomain/JSONParse.swift",
    "core/Sources/LorvexDomain/JSONValue.swift",
}

LOWER_SHA256 = re.compile(r"^[0-9a-f]{64}$")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def violations() -> list[str]:
    failures: list[str] = []
    try:
        lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"cannot read {LOCK_PATH.relative_to(APPLE_ROOT)}: {error}"]

    if lock.get("format_version") != "1":
        failures.append("backup_v1_contract.lock must declare format_version \"1\"")
    golden_sha = lock.get("golden_payload_sha256")
    if not isinstance(golden_sha, str) or not LOWER_SHA256.fullmatch(golden_sha):
        failures.append(
            "backup_v1_contract.lock golden_payload_sha256 must be lowercase SHA-256"
        )
    production_json_sha = lock.get("golden_production_json_sha256")
    if not isinstance(production_json_sha, str) or not LOWER_SHA256.fullmatch(
        production_json_sha
    ):
        failures.append(
            "backup_v1_contract.lock golden_production_json_sha256 must be lowercase SHA-256"
        )
    production_zip_sha = lock.get("golden_production_zip_sha256")
    if not isinstance(production_zip_sha, str) or not LOWER_SHA256.fullmatch(
        production_zip_sha
    ):
        failures.append(
            "backup_v1_contract.lock golden_production_zip_sha256 must be lowercase SHA-256"
        )

    locked_files = lock.get("files")
    if not isinstance(locked_files, dict):
        return failures + ["backup_v1_contract.lock files must be an object"]

    locked_paths = set(locked_files)
    for missing in sorted(REQUIRED_FROZEN_FILES - locked_paths):
        failures.append(f"v1 frozen source is absent from the lock: {missing}")
    for extra in sorted(locked_paths - REQUIRED_FROZEN_FILES):
        failures.append(f"unexpected path in the closed v1 source lock: {extra}")

    for relative in sorted(REQUIRED_FROZEN_FILES & locked_paths):
        expected = locked_files[relative]
        path = APPLE_ROOT / relative
        if not isinstance(expected, str) or not LOWER_SHA256.fullmatch(expected):
            failures.append(f"v1 lock hash for {relative} must be lowercase SHA-256")
            continue
        if not path.is_file():
            failures.append(f"frozen v1 source is missing: {relative}")
            continue
        actual = sha256(path)
        if actual != expected:
            remedy = (
                "Released wire: keep the v1 type intact and introduce a new "
                "versioned DTO/decoder."
                if is_launched()
                else "Pre-launch: if this edit is intentional, update the golden "
                "digests in BackupV1GoldenFixture.swift from the Swift test "
                "output and re-run with --seed."
            )
            failures.append(
                f"frozen v1 source changed: {relative} "
                f"(locked {expected[:16]}..., actual {actual[:16]}...). " + remedy
            )

    contract_path = APPLE_ROOT / "Sources/LorvexCore/Support/BackupV1Contract.swift"
    importer_path = APPLE_ROOT / "Sources/LorvexCore/Support/LorvexDataImporter+Decode.swift"
    exporter_path = APPLE_ROOT / "Sources/LorvexCore/Support/LorvexDataExporter.swift"
    archive_path = APPLE_ROOT / "Sources/LorvexCore/Support/BackupV1Archive.swift"
    inventory_path = (
        APPLE_ROOT / "Sources/LorvexCore/Support/BackupV1SingleFileInventory.swift"
    )
    graph_v1_validator_path = (
        APPLE_ROOT / "Sources/LorvexCore/Support/NativeTaskGraphV1Validator.swift"
    )
    graph_semantics_path = (
        APPLE_ROOT
        / "Sources/LorvexCore/Support/BackupV1NativeTaskGraphSemantics.swift"
    )
    recurrence_semantics_path = (
        APPLE_ROOT / "Sources/LorvexCore/Support/BackupV1RecurrenceSemantics.swift"
    )
    task_projection_path = (
        APPLE_ROOT / "Sources/LorvexCore/Support/BackupV1TaskProjectionConsistency.swift"
    )
    payload_preflight_path = (
        APPLE_ROOT / "Sources/LorvexCore/Support/BackupV1PayloadPreflight.swift"
    )
    graph_restore_adapter_path = (
        APPLE_ROOT / "Sources/LorvexCore/Support/NativeTaskGraphRestoreAdapter.swift"
    )
    graph_import_path = (
        APPLE_ROOT
        / "Sources/LorvexCore/Services/SwiftLorvexCoreService+NativeTaskGraphImport.swift"
    )
    wire_paths = [
        APPLE_ROOT / "Sources/LorvexCore/Support/BackupV1Wire.swift",
        APPLE_ROOT / "Sources/LorvexCore/Support/BackupV1PortableWire.swift",
        APPLE_ROOT / "Sources/LorvexCore/Support/BackupV1NativeTaskWire.swift",
    ]
    compatibility_test_paths = (
        APPLE_ROOT / "Tests/LorvexAppleTests/BackupFormatCompatibilityTests.swift",
        APPLE_ROOT / "Tests/LorvexAppleTests/BackupRestoreSafetyTests.swift",
    )
    fixture_path = APPLE_ROOT / "Tests/LorvexAppleTests/BackupV1GoldenFixture.swift"
    try:
        contract = contract_path.read_text(encoding="utf-8")
        importer = importer_path.read_text(encoding="utf-8")
        exporter = exporter_path.read_text(encoding="utf-8")
        archive = archive_path.read_text(encoding="utf-8")
        inventory = inventory_path.read_text(encoding="utf-8")
        graph_v1_validator = graph_v1_validator_path.read_text(encoding="utf-8")
        graph_semantics = graph_semantics_path.read_text(encoding="utf-8")
        recurrence_semantics = recurrence_semantics_path.read_text(encoding="utf-8")
        task_projection = task_projection_path.read_text(encoding="utf-8")
        payload_preflight = payload_preflight_path.read_text(encoding="utf-8")
        graph_restore_adapter = graph_restore_adapter_path.read_text(encoding="utf-8")
        graph_import = graph_import_path.read_text(encoding="utf-8")
        wire_sources = "\n".join(path.read_text(encoding="utf-8") for path in wire_paths)
        compatibility_tests = "\n".join(
            path.read_text(encoding="utf-8") for path in compatibility_test_paths
        )
        fixture = fixture_path.read_text(encoding="utf-8")
    except OSError as error:
        return failures + [f"cannot inspect v1 contract sources: {error}"]

    required_contract_fragments = (
        'formatVersion = "1"',
        'zipSchemaVersion = "1"',
        'nativeTaskGraphSchemaVersion = "1"',
        "maxSourceBytes = 64 * 1024 * 1024",
    )
    for fragment in required_contract_fragments:
        if fragment not in contract:
            failures.append(f"BackupV1Contract no longer pins `{fragment}`")

    required_importer_fragments = (
        "BackupV1Archive.decodeJSON(data)",
        "BackupV1Archive.decodeZip(",
        "BackupV1SingleFileInventory.validate(data, payload: payload)",
        "BackupV1PayloadPreflight.validate(payload)",
        "BackupV1Contract.nativeTaskGraphSchemaVersion",
    )
    for fragment in required_importer_fragments:
        if fragment not in importer:
            failures.append(f"v1 importer no longer uses its frozen branch: `{fragment}`")
    if "NativeTaskGraphSnapshot.currentSchemaVersion" in importer:
        failures.append(
            "v1 importer must not bind native graph decoding to the mutable current schema version"
        )

    required_inventory_fragments = (
        "allowedTopLevelKeys",
        "unexpectedJSONMember",
        "missingPayloadManifest",
        "manifest.entityCounts",
        "declaredKeys == observedKeys",
    )
    for fragment in required_inventory_fragments:
        if fragment not in inventory:
            failures.append(f"v1 single-file inventory drifted: `{fragment}`")

    if 'static let schemaVersion = "1"' not in graph_v1_validator:
        failures.append("the retained native task-graph validator must pin schema version 1")
    if "currentSchemaVersion" in graph_v1_validator:
        failures.append(
            "the retained native task-graph-v1 validator must not bind to the mutable current version"
        )
    for mutable_helper in (
        "ValidationRecurrence",
        "Recurrence.generateInstanceKey",
        "TaskRecurrenceSuccessorID",
        "Hlc.isOperationally",
        "Hlc.hasOperational",
        "DependencyEdge.encodeEntityId",
        "SyncEntityId",
        "IsoDate",
        "SyncTimestamp",
        "Timezone.parseTimezoneName",
    ):
        if mutable_helper in graph_v1_validator or mutable_helper in task_projection:
            failures.append(
                "public-v1/native-graph-v1 semantics depend on mutable current helper "
                f"`{mutable_helper}`"
            )
    for fragment in (
        "private static let taskStatuses",
        "private static let deferReasons",
        "private static let recurrenceKeys",
        "private static let syncedEntityKinds",
        "private static let maxRecurrenceExceptions = 400",
        "private static let maxPayloadSchemaVersion: UInt32 = 101",
        "private static let maxRawPayloadJSONBytes = 256 * 1024",
        "private static let maxSourceDeviceIDBytes = 128",
    ):
        if fragment not in graph_v1_validator:
            failures.append(f"native task-graph-v1 semantics are no longer pinned: `{fragment}`")
    for fragment in (
        "private static let maxOperationalHLCPhysicalMs",
        "static func recurrenceInstanceKey",
        "static func recurrenceSuccessorID",
        "static func dependencyEntityID",
        "static func isCanonicalTaskSyncIdentity",
        "static func isStableTimezoneIdentifier",
    ):
        if fragment not in graph_semantics:
            failures.append(f"frozen graph-v1 primitive semantics lost `{fragment}`")
    for fragment in (
        'private static let frequencies: Set<String> = ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"]',
        "private static let maxInterval: Int64 = 10_000",
        "static func canonicalize(_ raw: String)",
        "COUNT and UNTIL are mutually exclusive",
        "ANCHOR=completion cannot combine with",
    ):
        if fragment not in recurrence_semantics:
            failures.append(f"frozen recurrence semantics lost `{fragment}`")
    for fragment in (
        "LorvexDataImporter.validateBackupV1TaskProjection(payload)",
        "NativeTaskGraphRestoreAdapter.prepareVersion1(graph)",
        "validateParentMemberRelationships(payload)",
    ):
        if fragment not in payload_preflight:
            failures.append(f"public-v1 semantic preflight lost `{fragment}`")
    for fragment in (
        "portableProjection(",
        "nativeProjection(",
        "permitsExactNativeRestore(",
        "different overlapping semantic content",
    ):
        if fragment not in task_projection:
            failures.append(f"public-v1 task projection guard lost `{fragment}`")
    required_restore_fragments = (
        "case NativeTaskGraphV1Validator.schemaVersion",
        "prepareVersion1(",
        "NativeTaskGraphV1Validator.validate(",
        "adaptVersion1ToCurrent(",
    )
    for fragment in required_restore_fragments:
        if fragment not in graph_restore_adapter:
            failures.append(f"native task-graph v1 restore adapter drifted: `{fragment}`")
    if "NativeTaskGraphRestoreAdapter.prepare(" not in graph_import:
        failures.append("native task-graph import bypasses the versioned restore adapter")

    required_exporter_fragments = (
        "BackupV1Archive.renderJSON(payload)",
        "BackupV1Archive.renderZip(",
    )
    for fragment in required_exporter_fragments:
        if fragment not in exporter:
            failures.append(f"v1 exporter bypasses its frozen producer: `{fragment}`")

    required_archive_fragments = (
        "enum BackupV1ZipMember: String, CaseIterable",
        "for member in BackupV1ZipMember.allCases",
        "BackupV1ZipMember(path: entry.path)",
        "BackupV1Payload(current: payload)",
        "BackupV1Payload.self",
        "BackupV1PayloadPreflight.validate(payload)",
        "BackupV1PayloadPreflight.validateParentMemberRelationships(payload)",
    )
    for fragment in required_archive_fragments:
        if fragment not in archive:
            failures.append(f"v1 archive registry/codec drifted: `{fragment}`")
    for member in (
        "tasks.json",
        "native_task_graph.json",
        "lists.json",
        "tags.json",
        "habits.json",
        "calendar_series_cutovers.json",
        "calendar_events.json",
        "daily_reviews.json",
        "current_focus.json",
        "focus_schedules.json",
        "task_calendar_event_links.json",
        "memory.json",
        "preferences.json",
    ):
        if f'= "{member}"' not in archive:
            failures.append(f"v1 ZIP registry lost frozen member `{member}`")

    if "typealias BackupV1" in wire_sources:
        failures.append("v1 wire DTOs must not alias mutable current export models")
    required_wire_fragments = (
        "struct BackupV1Payload: Codable",
        "struct BackupV1ZipManifest: Codable",
        "struct BackupV1MemoryEntry: Codable",
        "struct BackupV1ChecklistItem: Codable",
        "struct BackupV1NativeTaskGraph: Codable",
    )
    for fragment in required_wire_fragments:
        if fragment not in wire_sources:
            failures.append(f"v1 self-contained wire surface lost `{fragment}`")

    required_test_fragments = (
        "expectedProductionJSONSHA256",
        "expectedProductionZipSHA256",
        "BackupV1ZipMember.allowedPaths",
        "canonicalJSON(entry.data)",
        "v1RejectsMalformedSyncedIdentities",
        "singleFileJSONEnforcesInventoryAndCounts",
        "v1NativeGraphUsesVersionedRestoreAdapter",
        "restoresProductionShapedV1Fixture",
        "zipAndProducerEnforceParentMemberRelationships",
    )
    for fragment in required_test_fragments:
        if fragment not in compatibility_tests:
            failures.append(f"v1 production golden coverage lost `{fragment}`")

    fixture_match = re.search(
        r'expectedSHA256\s*=\s*"([0-9a-f]{64})"', fixture
    )
    if fixture_match is None:
        failures.append("BackupV1GoldenFixture must pin a lowercase expectedSHA256")
    elif isinstance(golden_sha, str) and fixture_match.group(1) != golden_sha:
        failures.append(
            "BackupV1GoldenFixture.expectedSHA256 disagrees with backup_v1_contract.lock"
        )

    production_json_match = re.search(
        r'expectedProductionJSONSHA256\s*=\s*"([0-9a-f]{64})"', fixture
    )
    if production_json_match is None:
        failures.append("BackupV1GoldenFixture must pin expectedProductionJSONSHA256")
    elif (
        isinstance(production_json_sha, str)
        and production_json_match.group(1) != production_json_sha
    ):
        failures.append(
            "BackupV1GoldenFixture.expectedProductionJSONSHA256 disagrees with the lock"
        )

    production_zip_match = re.search(
        r'expectedProductionZipSHA256\s*=\s*"([0-9a-f]{64})"', fixture
    )
    if production_zip_match is None:
        failures.append("BackupV1GoldenFixture must pin expectedProductionZipSHA256")
    elif (
        isinstance(production_zip_sha, str)
        and production_zip_match.group(1) != production_zip_sha
    ):
        failures.append(
            "BackupV1GoldenFixture.expectedProductionZipSHA256 disagrees with the lock"
        )

    return failures


def seed() -> int:
    """Regenerate the lock from the working tree (pre-launch only).

    File hashes are recomputed directly. The three golden digests are adopted
    from the constants pinned in ``BackupV1GoldenFixture.swift`` — the Swift
    backup suites verify those constants against the real encoders at runtime
    and print the actual digests on mismatch, so the fixture is the single
    hand-edited seed source and the lock never needs manual hash editing.
    """
    if is_launched():
        print(
            "backup v1 contract --seed refused: migration_policy.json is launched. "
            "The released v1 wire is immutable; introduce a new versioned "
            "DTO/decoder instead.",
            file=sys.stderr,
        )
        return 1
    try:
        fixture = FIXTURE_PATH.read_text(encoding="utf-8")
    except OSError as error:
        print(f"backup v1 contract --seed failed: {error}", file=sys.stderr)
        return 1
    digests = {}
    for lock_key, constant in (
        ("golden_payload_sha256", "expectedSHA256"),
        ("golden_production_json_sha256", "expectedProductionJSONSHA256"),
        ("golden_production_zip_sha256", "expectedProductionZipSHA256"),
    ):
        match = re.search(constant + r'\s*=\s*"([0-9a-f]{64})"', fixture)
        if match is None:
            print(
                f"backup v1 contract --seed failed: BackupV1GoldenFixture.swift "
                f"does not pin a lowercase SHA-256 for {constant}",
                file=sys.stderr,
            )
            return 1
        digests[lock_key] = match.group(1)
    files = {}
    for relative in sorted(REQUIRED_FROZEN_FILES):
        path = APPLE_ROOT / relative
        if not path.is_file():
            print(
                f"backup v1 contract --seed failed: frozen source missing: {relative}",
                file=sys.stderr,
            )
            return 1
        files[relative] = sha256(path)
    lock = {"format_version": "1", **digests, "files": files}
    LOCK_PATH.write_text(
        json.dumps(lock, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(
        f"seeded {LOCK_PATH.relative_to(APPLE_ROOT)}: {len(files)} frozen files, "
        "3 golden digests adopted from BackupV1GoldenFixture.swift"
    )
    return verify()


def verify() -> int:
    failures = violations()
    if failures:
        print("backup v1 contract verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    regime = "post-launch (frozen)" if is_launched() else "pre-launch (editable via --seed)"
    print(
        f"backup v1 contract verified: {len(REQUIRED_FROZEN_FILES)} frozen files, "
        f"closed 13-member ZIP registry, portable 64 MiB envelope, regime {regime}"
    )
    return 0


def main() -> int:
    if "--seed" in sys.argv[1:]:
        return seed()
    return verify()


if __name__ == "__main__":
    raise SystemExit(main())
