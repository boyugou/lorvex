# Encrypting User Data with CloudKit

Source: [Encrypting User Data](https://developer.apple.com/documentation/cloudkit/encrypting-user-data)

Last verified: 2026-07-10

## Apple Contract

- CloudKit encrypted fields are available in private and shared databases and
  are written through `CKRecord.encryptedValues`.
- Encryption state is a production-schema decision: an existing plaintext
  field cannot later be converted into an encrypted field.
- If the user's iCloud Keychain encryption material is reset, an operation can
  fail with `CKError.Code.zoneNotFound` and include
  `CKErrorUserDidResetEncryptedDataKey` in `userInfo`.
- Apple prescribes a distinct recovery for that case: delete the affected
  zones, recreate them, and upload locally cached data using the new key
  material.
- A manually deleted zone is a different condition (`userDeletedZone`) and
  must respect the user's deletion decision.

## Lorvex Mapping

Lorvex correctly distinguishes `userDeletedZone` from ordinary
`zoneNotFound`, and its generic missing-zone recovery invalidates local zone
and record metadata, re-enqueues a local snapshot, recreates the zone, and
re-fetches from a nil token.

The implementation does not inspect
`CKErrorUserDidResetEncryptedDataKey`. Consequently the key-reset case takes
the generic `zoneNotFound` branch without the explicit delete step or a
key-reset-specific test and diagnostic. That is close to Apple's required
shape, but it is not evidence that the documented recovery has actually been
implemented for this distinct cause.

Relevant code:

- `CloudSyncEngineCoordinator+AccountGate.swift:365-429`
- `CloudSyncRecordPushing.swift:56-93`
- `CloudSyncRecordPushing.swift:95-130`

## Freeze Check

Before production schema promotion, add a deterministic injected-error test
whose `CKError(.zoneNotFound)` carries the reset flag. The expected operation
ordering and user-visible outcome should be specified even if Apple does not
provide a convenient real-account procedure for inducing a key reset.

