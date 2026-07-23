# Apple sync payload contracts

Each `NNN.json` file is the Apple sync wire contract for payload schema version
`NNN`. `contract_format` is the manifest-file grammar (currently `3`), distinct
from that wire version. From the initial, still-unreleased `001.json`, every
entity declares operation-specific shapes and a typed field registry:

- `operations.upsert.required_keys` are present in every canonical upsert
  produced at that version, even when their JSON value is `null`;
- `operations.upsert.optional_keys` are allowed but may be absent;
- `operations.delete.shapes` are alternatives, matched independently. An empty
  list explicitly declares an upsert-only entity (currently `ai_changelog`,
  whose retention/full reset use physical record/zone deletion); the verifier
  does not flatten marker shapes into an over-broad union;
- `synthetic_keys` are upsert keys with no 1:1 base-table column, such as an
  embedded child collection or an outbox-injected field.

Every operation key points to one entry in `fields`. A field declares its exact
JSON `types`, including `null` when null is part of the wire contract. The
registry can additionally constrain string `format`/`enum`, numeric
`minimum`/`maximum`/`unit`, array `items`/cardinality/uniqueness, and recursively
typed object `properties`. Every object type must explicitly declare an object
policy. `additional_properties: false` closes it; an empty `properties` object
with `additional_properties: true` deliberately preserves arbitrary subkeys
(currently EventKit attendee dictionaries and preference JSON). These are
wire-level constraints, not a copy of SQLite affinity: focus-block start/end
values carry the `minute-of-day` unit, task estimates carry `minutes`, while
`09:30` fields use the `hh-mm` string format. The `uuid-or-inbox` format records
the canonical non-UUID list sentinel rather than pretending every list identity
is a UUID. Sync timestamps are the exact 24-byte millisecond UTC rendering
`YYYY-MM-DDTHH:MM:SS.mmmZ`.

Format 3 also records the two pieces of history that an individual field
registry cannot express:

- `shadow_reserved_keys` permanently reserves non-wire spellings that an older
  payload-shadow implementation stripped. A reserved spelling can never later
  become a wire field because that older client would erase it on round trip.
- `field_evolution` defines what a newer client does when a payload from an
  older schema version lacks a field. Version 1 has an empty object: its fields
  have no legacy-absence history. Every field later added to an existing entity
  contributes one immutable entry keyed by `entity.field`, for example:

  ```json
  "list.notes": {
    "introduced_in": 2,
    "legacy_insert_default": null,
    "legacy_update": "preserve",
    "meaning": "Optional user-authored list notes."
  }
  ```

  `legacy_update: preserve` prevents an older client's field-absent update from
  clearing a value already stored by a newer client. `legacy_insert_default` is
  the deterministic value used when that legacy upsert creates a row that does
  not yet exist on the receiving client; the verifier checks it recursively
  against the field's wire type, format, enum, range, and nested shape.
  `meaning` makes the fallback's product semantics explicit. A wholly new
  entity needs no entries because no older row of that entity can exist.
  `SyncPayloadEvolutionRuntimeContractTests` makes both declarations executable:
  for every historical entry it applies a real pre-introduction golden upsert
  through the current applier and requires the current outbound snapshot to emit
  the declared default, then proves a higher-HLC historical update preserves a
  distinct valid value. The test generates that value from the typed field spec
  and fails loudly when the spec has no generic distinct probe. It also pins
  `SyncPayloadEvolution.fieldIntroductions`, the production convergence-re-emit
  map, exactly to the manifest metadata.

  A stricter rule applies to `calendar_event`, `habit`,
  `habit_reminder_policy`, `memory`, `tag`, and `task`. Those aggregates can
  merge independently minted rows with different IDs. Their whole-row HLC does
  not retain enough per-field provenance to infer how a field absent from an
  older payload should survive that collision. The verifier therefore rejects
  every `field_evolution` entry for those entities today; there is no waiver.
  Such a field may ship only in one atomic change that teaches the verifier its
  exact reviewed coverage, registers an executable entity-specific adapter in
  `PayloadEvolutionCollisionAdapterRegistry`, and adds opposite-arrival-order
  convergence probes. The runtime checks adapter coverage on every collision,
  not just one known-old envelope, because rows do not persist source payload
  schema provenance. Independently, every already-shipped runtime defers a
  cross-ID collision whenever any participant still has an opaque payload
  shadow. This generic hold is what prevents an older binary—one that cannot
  possibly contain the future adapter—from discarding the new field before an
  upgrade can promote it.

Each manifest also pins one checked-in canonical fixture under `fixtures/` by
relative path and SHA-256. The fixture contains exactly one populated upsert
envelope for every entity. It is intentionally reviewed and stored independently
from the current Swift builders and appliers: generating it from the code under
test would let two drifting implementations agree with each other. The verifier
rejects non-canonical JSON, a stale SHA, missing/duplicate entities, key-shape
drift, typed-value drift, and an upsert whose payload `version` differs from its
envelope `version`. Non-standard `NaN` and positive/negative infinity tokens are
rejected in manifests, defaults, embedded JSON strings, and golden fixtures.

The current file must match `LorvexVersion.payloadSchemaVersion`. Swift tests
validate the independent golden envelopes and execute real payload
builders/loaders, the final outbox transform, and real inbound appliers. The
final envelope is compared to both the operation shape and recursive field
contract. Payload-shadow owned keys are checked separately; they are not treated
as proof of outbound emission.

Before the first public release, `001.json` is the single draft contract and may
be corrected in place because no shipped client consumes it. Keep
`LorvexVersion.payloadSchemaVersion` at `1` and do not manufacture a compatibility
ladder for unshipped drafts.

After the first schema-freeze arm, wire evolution is additive. An existing
entity, field specification, required/optional classification, delete semantic,
or historical metadata entry cannot be removed or reinterpreted. To add a new
entity or an optional top-level field:

1. Increment `LorvexVersion.payloadSchemaVersion` by one.
2. Copy the previous manifest to the next contiguous `NNN.json` filename.
3. Set `payload_schema_version` to the new number. A field added to an existing
   entity must be optional in its upsert shape and must add a `field_evolution`
   entry whose `introduced_in` is exactly `NNN`. Carry all older entries forward
   byte-for-byte. Do not add entries for fields of a wholly new entity. Keep
   entity, shape, type, enum, and key arrays sorted and unique.
   For a cross-ID collision aggregate, first satisfy the adapter requirement
   above; the default verifier intentionally blocks the manifest otherwise.
4. Add a new independent canonical `fixtures/NNN.golden.json`, update the
   manifest's path and SHA-256, and review the example as a wire artifact rather
   than deriving it from the current runtime.
5. Run `apps/apple/script/verify_sync_payload_contract.py` and
   `cd apps/apple/core && swift test --filter SyncPayloadContractTests` and
   `swift test --filter SyncPayloadEvolutionRuntimeContractTests` and
   `swift test --filter SyncFieldRoundTripProbeTests`.

Any additional pre-release field should be added to its precise upsert or delete
shape in `001.json` rather than widening every delete.

Do not edit or delete a released manifest. At the first public release,
`apps/apple/script/verify_schema_freeze.py --arm` atomically captures the SHA-256
of every current manifest in
`schema/migration_policy.json:frozen_baseline.sync_payload_contracts`. Later
releases may append a new manifest, but the verification gate rejects any
mutation of a previously frozen version. Re-run and commit `--arm` before each
later public archive; the release gate rejects an appended current manifest
that has not yet been captured.

These manifests govern the Apple implementation only. They do not impose schema
or wire-format parity on the Tauri app.
