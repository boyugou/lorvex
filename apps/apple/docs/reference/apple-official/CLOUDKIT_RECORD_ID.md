# CKRecord.ID

Source: [CKRecord.ID](https://developer.apple.com/documentation/cloudkit/ckrecord/id)

Last verified: 2026-07-10

## Apple Contract

A CloudKit record ID is record metadata made from a record-name string and a
zone ID. Apps may supply meaningful custom names, or let CloudKit derive a
UUID-based name. The record ID is the database identity used to save and fetch
the record; it is distinct from encrypted record fields.

## Lorvex Mapping

Lorvex supplies a deterministic record name:

`SHA256(entity_type + NUL + entity_id)`

This is bounded and prevents the raw identifier from appearing literally. It
also gives every device the same record identity without synchronizing a
separate lookup table, which is valuable for conflict-safe upserts.

It is not fully opaque for low-entropy inputs. The repository itself defines
date strings as the natural IDs for `daily_review`, `current_focus`, and
`focus_schedule`, and defines a small public catalog of preference keys. A
party that sees record IDs can precompute the SHA-256 value for plausible
`(type, id)` pairs and recognize those records. This is a cryptographic
inference from Apple's record-ID contract and Lorvex's naming function, not an
Apple statement about SHA-256.

Examples of readily enumerable inputs include:

- `daily_review\0YYYY-MM-DD`;
- `current_focus\0YYYY-MM-DD`;
- `focus_schedule\0YYYY-MM-DD`;
- `preference\0timezone`, `preference\0theme`, and the other fixed keys.

High-entropy UUID entity IDs do not have the same dictionary-recovery problem.
Payload contents remain protected; the leak is entity presence/type/date and
linkability, alongside ordinary CloudKit record metadata.

## Freeze Decision

Lorvex accepts this bounded metadata exposure and keeps the deterministic hash
as the frozen record-identity contract. The source and schema comments describe
the limitation directly rather than treating the hash as a secrecy boundary.

The alternative — a keyed deterministic identifier — would require a durable
cross-device secret bootstrap, conflict resolution for simultaneous first-device
creation, and explicit recovery after account or encrypted-key reset. Losing or
forking that secret would make otherwise valid records undiscoverable and split
the fleet's write namespace. That availability and recovery cost is
disproportionate to hiding the presence of a small set of already-enumerable
record categories; payload contents and every envelope field remain encrypted.

A public salt or a random prefix stored next to the records does not prevent
the CloudKit service from testing guesses. Random record IDs alone would also
remove the deterministic identity that current multi-device upserts rely on.

Changing record names later would create new CloudKit records and require a
migration/deletion protocol. Do not revisit this contract as a cosmetic privacy
cleanup; revisit it only if the product threat model changes enough to justify
the new key lifecycle and a versioned fleet migration.
