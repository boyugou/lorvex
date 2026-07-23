# CKRecord

Source: [CKRecord](https://developer.apple.com/documentation/cloudkit/ckrecord)

Last verified: 2026-07-10

## Apple Contract

- Non-asset data in one record must not exceed 1 MB.
- Production rejects unknown record types and unknown fields.
- When mirroring records into a local database, archive the record's system
  fields so later saves can carry its record ID and current change tag.

## Lorvex Mapping

- Lorvex applies a lower payload ceiling before constructing a CloudKit record.
- `FileCloudSyncRecordSystemFieldsStore` archives the CloudKit system fields and
  the pusher uses `.ifServerRecordUnchanged`.
- Missing cache is recoverable through the conflict path.

## Audit Conclusion

The record-size and system-field design is sound. The cache is reconstructible
transport metadata, which matters for its backup classification; it should not
share lifecycle assumptions with user consent state merely because both are
small JSON/text files.
