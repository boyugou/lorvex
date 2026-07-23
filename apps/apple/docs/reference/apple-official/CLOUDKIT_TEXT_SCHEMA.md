# Integrating a Text-Based Schema into Your Workflow

Source: [Integrating a text-based schema into your workflow](https://developer.apple.com/documentation/cloudkit/integrating-a-text-based-schema-into-your-workflow)

Last verified: 2026-07-10

## Apple Contract

- Keep the CloudKit textual schema with the source that depends on it.
- For an existing container, download the authoritative schema instead of
  reconstructing it manually.
- CloudKit rejects a schema update that would cause production data loss, such
  as removing a production record type or field.
- Field options and data types are part of the durable contract.

## Lorvex Mapping

`cloudkit/schema.ckdb` is versioned and
`script/verify_cloudkit_sync_readiness.py` cross-checks its field names and
encryption classification against `CloudSyncEnvelopeRecord`. This is a strong
source-level invariant.

The release process should still make exported development and production
schemas explicit artifacts. A hand-maintained file can drift from CloudKit
Console even when internal source checks are green.

## Change Policy

After first production deployment:

- never rename or repurpose an existing field;
- add a new encrypted field only if envelope versioning cannot represent the
  change;
- keep unknown envelope versions fail-safe for older clients; and
- prove forward/backward behavior before deploying the additive schema.
