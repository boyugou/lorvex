# cloudkit/ - Apple Swift CloudKit schema template

`schema.ckdb` is the CloudKit record-type template. The app syncs through
`CKSyncEngine` into one custom zone named `Lorvex` in the private database of
`iCloud.com.lorvex.apple`. The engine saves the zone itself, so the template
declares record types only.

Every record in that zone has the record type `LorvexEntity`, an
end-to-end-encrypted envelope. All seven wire fields (`entity_type`,
`entity_id`, `operation`, `version`, `payload_schema_version`, `payload`, and
`device_id`) are encrypted fields written client-side through
`CKRecord.encryptedValues`, and the type declares no custom plaintext fields.
The record name is the SHA-256 hex of the entity type and id, so the only
identity CloudKit sees in the clear is that hash. A delete is a `LorvexEntity`
record with `operation = delete`, never a CloudKit record deletion.

The template also declares record types that the app neither reads nor writes:
`LorvexZoneEpoch`, `LorvexServerClock`, `LorvexGenerationRoot`,
`LorvexGenerationSeal`, `LorvexTraversalWitness`,
`LorvexAuditRetentionMetadata`, and `LorvexGenerationWake`. CloudKit never
removes record types that have been deployed to Production, so the template
keeps declaring them to stay compatible with the deployed Production schema.

`deploy-schema.sh` deploys the template to the Development environment of
`iCloud.com.lorvex.apple` by default. Run it with no arguments for a normal
validate-and-import pass, or with `--reset` to reset Development to Production's
schema and delete its data before validating and importing the template. The
script rejects every other argument and every non-Development environment;
Production promotion remains a manual CloudKit Console operation.

The checked-in schema is necessary but not sufficient release evidence. Before
submission, deploy the exact Development schema, exercise multi-device sync
there, promote it to Production in CloudKit Console, and preserve the exported
Production schema plus the signed archive's container entitlement as release
evidence.

The Apple Swift app is the only product path that uses this container.
