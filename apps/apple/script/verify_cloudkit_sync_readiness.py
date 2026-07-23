#!/usr/bin/env python3
"""Verify CloudKit readiness metadata and sync coverage for EVERY syncable kind.

The syncable inventory is derived from the canonical authority —
``EntityKind.allSyncableTypes`` in ``core/Sources/LorvexDomain/NamingEntity.swift``
— never from a hand-maintained list. For each derived kind the gate asserts:

1. an inbound applier handles it AND is registered in
   ``EntityApplierRegistry.defaultEntityAppliers()`` (ApplyDispatch.swift);
2. the write surface enqueues outbound Upsert envelopes for it
   (a literal ``kind: .<case>`` in an ``enqueue*Upsert*`` call in
   ``Sources/LorvexCore/Services/SwiftLorvexCoreService+*.swift``);
3. the write surface enqueues outbound Delete envelopes for it (same, for
   ``enqueue*Delete*``).

``entity_redirect`` is intentionally a dedicated protocol primitive rather
than a registered domain applier or a UI write-surface call. The gate therefore
recognizes only its explicit ``Apply`` dispatch and ``EntityRedirect`` producer;
its permanent, absorbing alias contract is upsert-only.

Kinds that intentionally skip an outbound lane carry a named, documented
allow-entry in ``DIRECTIONALITY_EXCEPTIONS``; the gate fails on unknown or
stale entries, so an exception can never linger past the code it describes.
Local-only kinds (``device_state``, ``import_session``) stay out of scope
automatically because they are not in ``allSyncableTypes``.

The gate also cross-checks the Swift readiness capability ids against the
release strategy and the per-field encryption split against the CloudKit
schema template.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from release_strategy import CLOUDKIT_SYNC_READINESS


ROOT = Path(__file__).resolve().parents[1]
SWIFT_READINESS = ROOT / "Sources" / "LorvexCloudSync" / "CloudSyncReadiness.swift"
SYNC_NAMING = ROOT / "core" / "Sources" / "LorvexDomain" / "NamingEntity.swift"
SYNC_APPLY_DISPATCH = ROOT / "core" / "Sources" / "LorvexSync" / "ApplyDispatch.swift"
SYNC_APPLIERS_DIR = ROOT / "core" / "Sources" / "LorvexSync"
CORE_SERVICE_DIR = ROOT / "Sources" / "LorvexCore" / "Services"
ENVELOPE_RECORD = ROOT / "Sources" / "LorvexCloudSync" / "CloudSyncEnvelopeRecord.swift"
ZONE_EPOCH_RECORD = ROOT / "Sources" / "LorvexCloudSync" / "CloudSyncZoneEpochRecord.swift"
SERVER_CLOCK_RECORD = ROOT / "Sources" / "LorvexCloudSync" / "CloudSyncServerClock.swift"
AUDIT_RETENTION_METADATA = (
    ROOT / "Sources" / "LorvexCloudSync" / "CloudSyncAuditRetentionMetadata.swift"
)
CKDB_SCHEMA = ROOT.parents[1] / "cloudkit" / "schema.ckdb"


# The only readiness properties an allow-entry may waive. Inbound apply is
# never exceptable: ``allSyncableTypes`` IS the set an inbound envelope's
# `entity_type` is accepted against, so every member must dispatch to a
# registered applier.
EXCEPTABLE_PROPERTIES = {"outbound_upsert", "outbound_delete"}

# Named directionality exceptions: wire kind -> waived property -> reason.
# Each reason cites the code-level contract that makes the missing lane
# intentional. The gate fails if an entry names a kind outside the authority
# or if the waived lane gains coverage (stale entry), so this table cannot
# silently drift from the Swift code it describes.
DIRECTIONALITY_EXCEPTIONS: dict[str, dict[str, str]] = {
    "ai_changelog": {
        "outbound_delete": (
            "append-only audit envelope stream: no ai_changelog delete envelope "
            "exists. Retention instead converges through the account-scoped, "
            "monotonic audit frontier and a durable exact-zone physical CloudKit "
            "purge queue; inbound apply rejects and re-queues records below that "
            "frontier. Upserts remain emit-once and deduplicate by id on peers."
        ),
    },
    "daily_review": {
        "outbound_delete": (
            "no local delete operation exists: daily reviews are add/amend-only "
            "day-keyed rows (SwiftLorvexCoreService+Review.swift), so there is "
            "no delete to emit; inbound deletes still apply via DailyReviewApplier."
        ),
    },
    "calendar_series_cutover": {
        "outbound_delete": (
            "durable recurrence boundaries are remove-wins, upsert-only state: "
            "deletion is represented by a full upsert with state='deleted', and "
            "an ordinary Delete envelope is invalid so the absorbing barrier can "
            "never enter tombstone GC"
        ),
    },
    "entity_redirect": {
        "outbound_delete": (
            "permanent same-type aliases are absorbing, upsert-only state: an alias "
            "is never deleted or represented by a sync_tombstones death envelope"
        ),
    },
}


SWIFT_TO_RELEASE_ID = {
    "export": "outbound_record_export",
    "subscription": "private_database_subscription",
    "remote-refresh": "remote_change_refresh",
    "inbound-apply": "inbound_record_application",
    "change-token": "change_token_checkpointing",
}


def swift_readiness_ids(source: str) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {"ready": [], "pending": []}
    pattern = re.compile(
        r'Capability\(\s*id:\s*"([^"]+)".*?status:\s*\.(ready|pending)',
        flags=re.DOTALL,
    )
    for swift_id, status in pattern.findall(source):
        release_id = SWIFT_TO_RELEASE_ID.get(swift_id)
        if release_id is None:
            result.setdefault("unknown", []).append(swift_id)
            continue
        result[status].append(release_id)
    return result


def cloudkit_sync_readiness_failures(
    swift_source: str,
    expected: dict[str, list[str]] = CLOUDKIT_SYNC_READINESS,
) -> list[str]:
    actual = swift_readiness_ids(swift_source)
    failures: list[str] = []

    unknown = actual.get("unknown", [])
    if unknown:
        failures.append(f"CloudKit readiness declares unknown Swift capability id(s): {unknown}")

    for status in ["ready", "pending"]:
        if actual.get(status, []) != expected.get(status, []):
            failures.append(
                f"CloudKit readiness {status} mismatch: "
                f"expected {expected.get(status, [])!r}, got {actual.get(status, [])!r}"
            )

    declared = set(actual.get("ready", [])) | set(actual.get("pending", []))
    expected_declared = set(expected.get("ready", [])) | set(expected.get("pending", []))
    missing = sorted(expected_declared - declared)
    if missing:
        failures.append(f"CloudKit readiness missing release capability id(s): {missing}")
    extra = sorted(declared - expected_declared)
    if extra:
        failures.append(f"CloudKit readiness has extra release capability id(s): {extra}")

    return failures


def naming_wire_map(naming_source: str) -> dict[str, str]:
    """Member name -> canonical wire string, from NamingEntity.swift.

    Merges the ``static let x = "wire"`` naming constants (``EntityName.x``)
    with the ``case x = "wire"`` declarations of the ``EntityKind`` enum, so
    both constant references and enum-case names resolve. ``EdgeName``
    constants live in another Swift file, but every edge has an identically
    named ``EntityKind`` case in this file, so edge references resolve through
    the case map.
    """
    pairs = re.findall(r'\bstatic let\s+(\w+)\s*=\s*"([^"]+)"', naming_source)
    pairs += re.findall(r'\bcase\s+(\w+)\s*=\s*"([^"]+)"', naming_source)
    return dict(pairs)


def syncable_kinds(naming_source: str) -> tuple[list[tuple[str, str]], list[str]]:
    """Derive the syncable inventory from ``EntityKind.allSyncableTypes``.

    Returns ``(kinds, failures)`` where ``kinds`` is the ordered list of
    ``(enum_case_name, wire_string)`` pairs. Every array member must resolve to
    a wire string AND to an ``EntityKind`` case (the case name is what outbox
    enqueue call sites spell as ``kind: .<case>``); anything unresolvable is a
    failure, never a silent skip.
    """
    failures: list[str] = []
    block = re.search(
        r"static let allSyncableTypes:\s*\[String\]\s*=\s*\[(.*?)\]",
        naming_source,
        flags=re.DOTALL,
    )
    if block is None:
        return [], ["could not parse EntityKind.allSyncableTypes from NamingEntity.swift"]
    members = re.findall(r"\b(?:EntityName|EdgeName)\.(\w+)", block.group(1))
    if not members:
        return [], ["EntityKind.allSyncableTypes parsed to an empty inventory"]

    wire_map = naming_wire_map(naming_source)
    case_by_wire = {
        wire: case for case, wire in re.findall(r'\bcase\s+(\w+)\s*=\s*"([^"]+)"', naming_source)
    }
    kinds: list[tuple[str, str]] = []
    for member in members:
        wire = wire_map.get(member)
        if wire is None:
            failures.append(
                f"allSyncableTypes member {member!r} has no wire-string declaration "
                "in NamingEntity.swift"
            )
            continue
        case = case_by_wire.get(wire)
        if case is None:
            failures.append(
                f"syncable wire type {wire!r} has no EntityKind case in NamingEntity.swift"
            )
            continue
        kinds.append((case, wire))
    return kinds, failures


def registered_applier_types(apply_dispatch_source: str) -> list[str] | None:
    """Applier type names instantiated in ``defaultEntityAppliers()``, or
    ``None`` when the registry body cannot be located."""
    match = re.search(
        r"func defaultEntityAppliers\(\)[^{]*\{\s*\[(.*?)\]\s*\}",
        apply_dispatch_source,
        flags=re.DOTALL,
    )
    if match is None:
        return None
    return re.findall(r"\b(\w+)\(\)", match.group(1))


def applier_handled_wires(
    sync_sources: dict[str, str],
    wire_map: dict[str, str],
) -> tuple[dict[str, set[str]], list[str]]:
    """Map each applier type to the wire strings its ``handledEntityTypes``
    declares, scanning the LorvexSync sources.

    Each ``handledEntityTypes: [String] { [ ... ] }`` body is attributed to the
    nearest preceding type declaration. Items resolve from ``EntityName.x`` /
    ``EdgeName.x`` constants, ``EntityKind.x.asString``, or string literals; an
    unresolvable item is a failure (the protocol requirement's ``{ get }`` body
    never matches). Returns ``(handled_by_type, failures)``.
    """
    failures: list[str] = []
    handled: dict[str, set[str]] = {}
    type_decl = re.compile(r"\b(?:struct|class|actor|enum|extension)\s+(\w+)")
    handled_decl = re.compile(r"handledEntityTypes:\s*\[String\]\s*\{\s*\[([^\]]*)\]")
    for file_name, source in sync_sources.items():
        decls = [(m.start(), m.group(1)) for m in type_decl.finditer(source)]
        for match in handled_decl.finditer(source):
            owner = None
            for pos, type_name in decls:
                if pos < match.start():
                    owner = type_name
                else:
                    break
            if owner is None:
                failures.append(
                    f"{file_name}: handledEntityTypes declared outside any type"
                )
                continue
            for item in match.group(1).split(","):
                item = item.strip()
                if not item:
                    continue
                literal = re.fullmatch(r'"([^"]+)"', item)
                if literal:
                    handled.setdefault(owner, set()).add(literal.group(1))
                    continue
                ref = re.fullmatch(
                    r"(?:EntityName|EdgeName)\.(\w+)|EntityKind\.(\w+)\.asString", item
                )
                member = ref and (ref.group(1) or ref.group(2))
                wire = member and wire_map.get(member)
                if wire is None:
                    failures.append(
                        f"{file_name}: unresolvable handledEntityTypes item {item!r} "
                        f"in {owner}"
                    )
                    continue
                handled.setdefault(owner, set()).add(wire)
    return handled, failures


# A literal `kind: .<case>` inside an outbox enqueue call. The `[^()]*?` bound
# keeps the match inside one argument list (no enqueue passes a parenthesized
# expression before `kind:`), so a helper's variable `kind: kind` or a later
# unrelated call can never satisfy the pattern.
UPSERT_ENQUEUE = re.compile(r"enqueue\w*Upserts?\(\s*[^()]*?kind:\s*\.(\w+)")
DELETE_ENQUEUE = re.compile(r"enqueue\w*Deletes?\(\s*[^()]*?kind:\s*\.(\w+)")


def outbox_enqueued_case_names(service_sources: dict[str, str]) -> tuple[set[str], set[str]]:
    """``(upsert_cases, delete_cases)``: the EntityKind case names that appear
    as a literal ``kind: .<case>`` in an enqueue call anywhere on the write
    surface (including the edge-upsert helpers in +OutboxFlush.swift)."""
    upserts: set[str] = set()
    deletes: set[str] = set()
    for source in service_sources.values():
        upserts.update(UPSERT_ENQUEUE.findall(source))
        deletes.update(DELETE_ENQUEUE.findall(source))
    return upserts, deletes


def dedicated_entity_redirect_coverage(
    sync_sources: dict[str, str],
) -> tuple[bool, bool]:
    """Return dedicated ``(inbound, outbound_upsert)`` redirect coverage.

    This primitive deliberately bypasses ``defaultEntityAppliers()`` and the
    app-facing Core service. Require the named special dispatch plus its
    upsert-only validation, and require the atomic alias producer to enqueue the
    canonical independent record. Generic mentions of ``entity_redirect`` do
    not satisfy either lane.
    """
    apply_source = sync_sources.get("Apply.swift", "")
    redirect_source = sync_sources.get("EntityRedirect.swift", "")
    inbound = bool(
        re.search(
            r"if\s+envelope\.entityType\s*==\s*\.entityRedirect\s*\{"
            r".*?EntityRedirect\.applyInbound\(",
            apply_source,
            flags=re.DOTALL,
        )
        and re.search(
            r"static func applyInbound\(.*?"
            r"guard\s+envelope\.operation\s*==\s*\.upsert",
            redirect_source,
            flags=re.DOTALL,
        )
    )
    outbound_upsert = bool(
        re.search(
            r"static func upsertAndEnqueue\(.*?"
            r"try\s+enqueue\(db,\s*record:\s*outcome\.record,\s*deviceId:\s*deviceId\)",
            redirect_source,
            flags=re.DOTALL,
        )
        and re.search(
            r"static func makeEnvelope\(.*?entityType:\s*\.entityRedirect,"
            r".*?operation:\s*\.upsert",
            redirect_source,
            flags=re.DOTALL,
        )
    )
    return inbound, outbound_upsert


def cloudkit_entity_coverage_failures(
    naming_source: str,
    apply_dispatch_source: str,
    sync_sources: dict[str, str],
    service_sources: dict[str, str],
    exceptions: dict[str, dict[str, str]] = DIRECTIONALITY_EXCEPTIONS,
) -> list[str]:
    """Assert full sync readiness for every kind in ``allSyncableTypes``.

    Per kind: a registered inbound applier, an outbound upsert enqueue, and an
    outbound delete enqueue — the latter two waivable only through a documented
    entry in ``exceptions``. Also validates the exception table itself (unknown
    kinds, unknown properties, stale entries all fail).
    """
    kinds, failures = syncable_kinds(naming_source)
    if not kinds:
        return failures

    known_wires = {wire for _, wire in kinds}
    for wire, properties in exceptions.items():
        if wire not in known_wires:
            failures.append(
                f"directionality exception names unknown syncable kind {wire!r}"
            )
            continue
        for prop in properties:
            if prop not in EXCEPTABLE_PROPERTIES:
                failures.append(
                    f"directionality exception for {wire!r} has unknown property "
                    f"{prop!r} (exceptable: {sorted(EXCEPTABLE_PROPERTIES)})"
                )

    registered = registered_applier_types(apply_dispatch_source)
    if registered is None:
        failures.append("could not parse defaultEntityAppliers() from ApplyDispatch.swift")
        return failures
    handled, handled_failures = applier_handled_wires(
        sync_sources, naming_wire_map(naming_source)
    )
    failures.extend(handled_failures)
    applied_wires: set[str] = set()
    for applier in registered:
        applied_wires.update(handled.get(applier, set()))

    upsert_cases, delete_cases = outbox_enqueued_case_names(service_sources)
    redirect_inbound, redirect_upsert = dedicated_entity_redirect_coverage(sync_sources)

    for case, wire in kinds:
        kind_exceptions = exceptions.get(wire, {})
        inbound_present = redirect_inbound if wire == "entity_redirect" else wire in applied_wires
        upsert_present = redirect_upsert if wire == "entity_redirect" else case in upsert_cases
        if not inbound_present:
            failures.append(f"CloudKit entity coverage missing inbound applier for {wire}")
        for prop, present, gap in [
            ("outbound_upsert", upsert_present, "outbound enqueue"),
            ("outbound_delete", case in delete_cases, "delete enqueue"),
        ]:
            if prop in kind_exceptions:
                if present:
                    failures.append(
                        f"stale directionality exception: {wire!r} now has "
                        f"{prop} coverage — remove the allow-entry"
                    )
            elif not present:
                failures.append(f"CloudKit entity coverage missing {gap} for {wire}")

    return failures


def field_encryption_contract(
    envelope_source: str,
) -> tuple[list[str], list[str] | None]:
    """Resolve ``CloudSyncEnvelopeRecord.Field.encrypted`` (and an optional
    ``.plaintext``) to the wire-field-name strings they carry.

    The Swift arrays list the Swift constant names (``entityType``, ``payload``,
    …); each constant is bound to its wire string (``"entity_type"``, …). Returns
    ``(plaintext_wire_names, encrypted_wire_names)``. The client encrypts every
    wire field, so there is no ``Field.plaintext`` declaration: an absent
    plaintext array resolves to ``[]`` (no plaintext wire field). ``encrypted``
    is ``None`` only when its declaration could not be located — a genuine parse
    failure.
    """
    const_to_wire = dict(re.findall(r'static let (\w+)\s*=\s*"([^"]+)"', envelope_source))

    def resolve(array_name: str) -> list[str] | None:
        match = re.search(
            rf"static let {array_name}(?:\s*:\s*\[[^\]]*\])?\s*=\s*\[([^\]]*)\]",
            envelope_source,
        )
        if match is None:
            return None
        names = [name.strip() for name in match.group(1).split(",") if name.strip()]
        return [const_to_wire[name] for name in names if name in const_to_wire]

    return (resolve("plaintext") or []), resolve("encrypted")


def ckdb_lorvex_entity_fields(ckdb_source: str) -> dict[str, bool]:
    """Map each non-system wire field declared on the `LorvexEntity` record type
    to whether it is declared ``ENCRYPTED``.

    System fields (the quoted ``"___…"`` columns) and ``GRANT`` clauses are
    skipped: only lower-case-initial unquoted field declarations are wire fields.
    Returns an empty dict when the record-type block cannot be located.
    """
    block = re.search(r"RECORD TYPE LorvexEntity\s*\((.*?)\);", ckdb_source, flags=re.DOTALL)
    if block is None:
        return {}
    fields: dict[str, bool] = {}
    for line in block.group(1).splitlines():
        match = re.match(r"\s*([a-z_][a-zA-Z0-9_]*)\s+(ENCRYPTED\s+)?[A-Z]", line)
        if match is None:
            continue
        fields[match.group(1)] = match.group(2) is not None
    return fields


def cloudkit_field_encryption_failures(
    envelope_source: str,
    ckdb_source: str,
) -> list[str]:
    """Cross-check the CloudKit template's per-field encryption declarations
    against the Swift client's plaintext/encrypted split.

    CloudKit fixes a field's encryption at creation, so a template that declares a
    field plaintext while the client writes it via ``encryptedValues`` (or vice
    versa) makes every push to a fresh container fail. This catches that drift in
    CI.
    """
    failures: list[str] = []
    plaintext, encrypted = field_encryption_contract(envelope_source)
    if encrypted is None or not encrypted:
        # The client encrypts every wire field, so `plaintext` legitimately
        # resolves to `[]` (no plaintext declaration); the `encrypted` array is
        # the authoritative wire-field set and must parse to a non-empty list.
        failures.append(
            "could not parse CloudSyncEnvelopeRecord.Field.encrypted from "
            f"{ENVELOPE_RECORD}"
        )
        return failures
    ckdb = ckdb_lorvex_entity_fields(ckdb_source)
    if not ckdb:
        failures.append(f"could not parse LorvexEntity fields from {CKDB_SCHEMA}")
        return failures

    for field in encrypted:
        if field not in ckdb:
            failures.append(f"schema.ckdb LorvexEntity is missing encrypted field {field!r}")
        elif not ckdb[field]:
            failures.append(
                f"schema.ckdb field {field!r} is declared plaintext but the client writes it "
                "via encryptedValues — declare it ENCRYPTED"
            )
    for field in plaintext:
        if field not in ckdb:
            failures.append(f"schema.ckdb LorvexEntity is missing plaintext field {field!r}")
        elif ckdb[field]:
            failures.append(
                f"schema.ckdb field {field!r} is declared ENCRYPTED but the client writes it "
                "in the clear — declare it plaintext"
            )
    classified = set(plaintext) | set(encrypted)
    for field in ckdb:
        if field not in classified:
            failures.append(
                f"schema.ckdb LorvexEntity field {field!r} is not classified in "
                "CloudSyncEnvelopeRecord.Field.encrypted"
            )
    return failures


def cloudkit_zone_epoch_schema_failures(
    zone_epoch_source: str,
    ckdb_source: str,
) -> list[str]:
    """Ensure the runtime's zone-epoch metadata record type is declared in the
    CloudKit template with the complete plaintext generation-readiness shape.

    The over-window resurrection guard saves an epoch record of its OWN record
    type (`CloudSyncZoneEpochRecord.recordType`). Production CloudKit rejects a
    save to an UNDECLARED record type, so a template missing it — or declaring the
    epoch/readiness/lease fields missing, encrypted, or mistyped — silently
    breaks the partial-generation barrier while every ordinary entity push still
    succeeds. This turns that "false green" into a gated failure.
    """
    failures: list[str] = []
    type_match = re.search(r'static let recordType\s*=\s*"([^"]+)"', zone_epoch_source)
    field_constants = {
        "protocolVersionField": "INT64",
        "epochField": "INT64",
        "stateField": "STRING",
        "activeEpochField": "INT64",
        "generationIDField": "STRING",
        "activeZoneField": "STRING",
        "readyWitnessField": "STRING",
        "candidateGenerationIDField": "STRING",
        "candidateZoneField": "STRING",
        "rebuildIdentifierField": "STRING",
        "rebuildOwnerField": "STRING",
        "rebuildPhaseField": "STRING",
        "leaseActivityAtField": "STRING",
        "retiredZonesField": "STRING",
        "tombstoneCompactionCutoffField": "STRING",
    }
    parsed_fields: dict[str, tuple[str, str]] = {}
    for constant, expected_type in field_constants.items():
        match = re.search(
            rf'static let {re.escape(constant)}\s*=\s*"([^"]+)"', zone_epoch_source
        )
        if match is not None:
            parsed_fields[constant] = (match.group(1), expected_type)
    if type_match is None or len(parsed_fields) != len(field_constants):
        failures.append(
            "could not parse recordType and generation-readiness field constants from "
            f"{ZONE_EPOCH_RECORD}"
        )
        return failures
    record_type = type_match.group(1)
    block = re.search(
        rf"RECORD TYPE {re.escape(record_type)}\s*\((.*?)\);", ckdb_source, flags=re.DOTALL
    )
    if block is None:
        failures.append(
            f"schema.ckdb is missing RECORD TYPE {record_type} — the runtime saves this "
            "record type but production CloudKit rejects an undeclared type"
        )
        return failures
    declarations: dict[str, re.Match[str]] = {}
    for line in block.group(1).splitlines():
        match = re.match(r"\s*([a-z_][a-zA-Z0-9_]*)\s+(ENCRYPTED\s+)?([A-Z0-9]+)", line)
        if match:
            declarations[match.group(1)] = match
    for field_name, expected_type in parsed_fields.values():
        field_decl = declarations.get(field_name)
        if field_decl is None:
            failures.append(
                f"schema.ckdb RECORD TYPE {record_type} is missing field {field_name!r}"
            )
            continue
        if field_decl.group(2) is not None:
            failures.append(
                f"schema.ckdb {record_type}.{field_name} is declared ENCRYPTED but the runtime "
                f"writes it in the clear — declare it plaintext {expected_type}"
            )
        if field_decl.group(3) != expected_type:
            failures.append(
                f"schema.ckdb {record_type}.{field_name} must be {expected_type}, "
                f"got {field_decl.group(3)!r}"
            )
    return failures


def cloudkit_server_clock_schema_failures(
    server_clock_source: str,
    ckdb_source: str,
) -> list[str]:
    """Pin the fixed plaintext server-clock singleton to its deployed shape."""
    failures: list[str] = []
    type_match = re.search(r'static let recordType\s*=\s*"([^"]+)"', server_clock_source)
    nonce_match = re.search(r'static let nonceField\s*=\s*"([^"]+)"', server_clock_source)
    if type_match is None or nonce_match is None:
        return [
            "could not parse recordType and nonceField from "
            f"{SERVER_CLOCK_RECORD}"
        ]
    record_type = type_match.group(1)
    nonce_field = nonce_match.group(1)
    block = re.search(
        rf"RECORD TYPE {re.escape(record_type)}\s*\((.*?)\);",
        ckdb_source,
        flags=re.DOTALL,
    )
    if block is None:
        return [
            f"schema.ckdb is missing RECORD TYPE {record_type} — the runtime saves this "
            "record type but production CloudKit rejects an undeclared type"
        ]
    declaration = re.search(
        rf"^\s*{re.escape(nonce_field)}\s+(ENCRYPTED\s+)?([A-Z0-9]+)",
        block.group(1),
        flags=re.MULTILINE,
    )
    if declaration is None:
        failures.append(
            f"schema.ckdb RECORD TYPE {record_type} is missing field {nonce_field!r}"
        )
        return failures
    if declaration.group(1) is not None:
        failures.append(
            f"schema.ckdb {record_type}.{nonce_field} is declared ENCRYPTED but the runtime "
            "writes it in the clear — declare it plaintext STRING"
        )
    if declaration.group(2) != "STRING":
        failures.append(
            f"schema.ckdb {record_type}.{nonce_field} must be STRING, "
            f"got {declaration.group(2)!r}"
        )
    return failures


def cloudkit_audit_retention_metadata_schema_failures(
    metadata_source: str,
    ckdb_source: str,
) -> list[str]:
    """Pin the audit-retention metadata record's all-encrypted wire shape.

    The record is fetched by fixed id and never queried by a custom field, so
    exposing its policy, activity cutoff, or policy HLC/device suffix in
    plaintext is both unnecessary and a privacy regression. CloudKit fixes
    encryption at field creation; catch Swift/template drift before promotion.
    """
    failures: list[str] = []
    type_match = re.search(r'static let recordType\s*=\s*"([^"]+)"', metadata_source)
    if type_match is None:
        return ["could not parse audit-retention metadata recordType"]

    expected_types = {
        "protocolVersionField": "INT64",
        "generationEpochField": "INT64",
        "generationIDField": "STRING",
        "frontierEpochField": "INT64",
        "cutoffTimestampField": "STRING",
        "cutoffEntityIDField": "STRING",
        "policyField": "STRING",
        "policyVersionField": "STRING",
        "policyAuthorizedEpochField": "INT64",
    }
    constants = dict(
        re.findall(r"static let (\w+Field)\s*=\s*\"([^\"]+)\"", metadata_source)
    )
    missing_constants = sorted(set(expected_types) - set(constants))
    if missing_constants:
        failures.append(
            "audit-retention metadata is missing Swift field constants: "
            + ", ".join(missing_constants)
        )
        return failures

    encrypted_match = re.search(
        r"static let encryptedFields\s*=\s*\[(.*?)\]",
        metadata_source,
        flags=re.DOTALL,
    )
    if encrypted_match is None:
        return ["could not parse audit-retention metadata encryptedFields"]
    encrypted_constants = {
        name.strip()
        for name in encrypted_match.group(1).split(",")
        if name.strip()
    }
    if encrypted_constants != set(expected_types):
        failures.append(
            "audit-retention metadata encryptedFields does not exactly classify "
            "the complete custom field set"
        )

    record_type = type_match.group(1)
    block = re.search(
        rf"RECORD TYPE {re.escape(record_type)}\s*\((.*?)\);",
        ckdb_source,
        flags=re.DOTALL,
    )
    if block is None:
        failures.append(f"schema.ckdb is missing RECORD TYPE {record_type}")
        return failures
    declarations: dict[str, re.Match[str]] = {}
    for line in block.group(1).splitlines():
        match = re.match(
            r"\s*([a-z_][a-zA-Z0-9_]*)\s+(ENCRYPTED\s+)?([A-Z0-9]+)",
            line,
        )
        if match:
            declarations[match.group(1)] = match

    expected_wire_names = {constants[name] for name in expected_types}
    for constant, expected_type in expected_types.items():
        field_name = constants[constant]
        declaration = declarations.get(field_name)
        if declaration is None:
            failures.append(
                f"schema.ckdb RECORD TYPE {record_type} is missing field {field_name!r}"
            )
            continue
        if declaration.group(2) is None:
            failures.append(
                f"schema.ckdb {record_type}.{field_name} is plaintext; "
                "declare it ENCRYPTED"
            )
        if declaration.group(3) != expected_type:
            failures.append(
                f"schema.ckdb {record_type}.{field_name} must be {expected_type}, "
                f"got {declaration.group(3)!r}"
            )
        encrypted_subscript = f"encryptedValues[{constant}]"
        if encrypted_subscript not in metadata_source:
            failures.append(
                f"runtime does not access {field_name!r} through CKRecord.encryptedValues"
            )
    for field_name in declarations:
        if field_name not in expected_wire_names:
            failures.append(
                f"schema.ckdb {record_type} has unclassified custom field {field_name!r}"
            )
    return failures


def main() -> int:
    failures: list[str] = []
    if not SWIFT_READINESS.exists():
        failures.append(f"CloudKit readiness Swift contract is missing: {SWIFT_READINESS}")
    else:
        failures.extend(cloudkit_sync_readiness_failures(SWIFT_READINESS.read_text(encoding="utf-8")))
    sync_sources = {
        path.name: path.read_text(encoding="utf-8")
        for path in SYNC_APPLIERS_DIR.glob("*.swift")
    }
    service_sources = {
        path.name: path.read_text(encoding="utf-8")
        for path in CORE_SERVICE_DIR.glob("SwiftLorvexCoreService+*.swift")
    }
    failures.extend(
        cloudkit_entity_coverage_failures(
            SYNC_NAMING.read_text(encoding="utf-8"),
            SYNC_APPLY_DISPATCH.read_text(encoding="utf-8"),
            sync_sources,
            service_sources,
        )
    )
    if not ENVELOPE_RECORD.exists():
        failures.append(f"CloudKit envelope-record contract is missing: {ENVELOPE_RECORD}")
    elif not CKDB_SCHEMA.exists():
        failures.append(f"CloudKit schema template is missing: {CKDB_SCHEMA}")
    else:
        ckdb_text = CKDB_SCHEMA.read_text(encoding="utf-8")
        failures.extend(
            cloudkit_field_encryption_failures(
                ENVELOPE_RECORD.read_text(encoding="utf-8"),
                ckdb_text,
            )
        )
        if ZONE_EPOCH_RECORD.exists():
            failures.extend(
                cloudkit_zone_epoch_schema_failures(
                    ZONE_EPOCH_RECORD.read_text(encoding="utf-8"),
                    ckdb_text,
                )
            )
        else:
            failures.append(f"CloudKit zone-epoch record contract is missing: {ZONE_EPOCH_RECORD}")
        if SERVER_CLOCK_RECORD.exists():
            failures.extend(
                cloudkit_server_clock_schema_failures(
                    SERVER_CLOCK_RECORD.read_text(encoding="utf-8"),
                    ckdb_text,
                )
            )
        else:
            failures.append(
                f"CloudKit server-clock record contract is missing: {SERVER_CLOCK_RECORD}"
            )
        if AUDIT_RETENTION_METADATA.exists():
            failures.extend(
                cloudkit_audit_retention_metadata_schema_failures(
                    AUDIT_RETENTION_METADATA.read_text(encoding="utf-8"),
                    ckdb_text,
                )
            )
        else:
            failures.append(
                "CloudKit audit-retention metadata contract is missing: "
                f"{AUDIT_RETENTION_METADATA}"
            )
    if failures:
        print("CloudKit sync readiness verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    kind_count = len(syncable_kinds(SYNC_NAMING.read_text(encoding="utf-8"))[0])
    print(
        "CloudKit sync readiness verification passed "
        f"({kind_count} syncable kinds covered)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
