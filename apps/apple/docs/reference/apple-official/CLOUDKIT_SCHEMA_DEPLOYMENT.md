# Deploying an iCloud Container's Schema

Source: [Deploying an iCloud container's schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)

Last verified: 2026-07-15

## Apple Contract

- App Store builds access the production environment.
- Before shipping, deploy the development schema to production.
- Deployment copies record types, fields, and indexes, but not development
  records.
- Production evolution is additive: record types and fields already in
  production cannot be deleted, and later deployments merge additions.

## Lorvex Mapping

The repository keeps domain evolution out of the CloudKit type system:

- one domain record type, `LorvexEntity`, shared by all 20 syncable entity
  types;
- seven control record types that the current `CKSyncEngine` transport
  never reads or writes; they stay in the template only because deployed
  production record types cannot be deleted;
- one bounded deterministic record name per logical entity, which hides the raw
  input strings but remains dictionary-testable for low-entropy natural IDs;
- seven encrypted string fields;
- no query dependency for inbound sync; and
- an envelope payload schema version independent of CloudKit field growth.

The checked-in template also retains CloudKit's system `Users` type. This is
well suited to a frozen production schema. The remaining risk is operational:
repository source cannot prove the live production container matches
`cloudkit/schema.ckdb`.

## Irreversible Release Gate

Before the first production deployment, export/download the development schema,
diff it against `cloudkit/schema.ckdb`, verify every `LorvexEntity` field and
every `LorvexAuditRetentionMetadata` custom field is encrypted, verify the other
control types contain only their documented non-user metadata, and verify no
accidental record types or fields are pending. Deploy, then export the production
schema back for archived evidence. Do not treat a successful app archive as
proof that this external state is correct.
