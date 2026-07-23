# CKRecord.encryptedValues

Source: [encryptedValues](https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues)

Last verified: 2026-07-10

## Apple Contract

- Encryption is available for new fields in private/shared databases.
- An existing plaintext field cannot later be converted into an encrypted
  field.
- Encrypted fields cannot be indexed and must not appear in CloudKit query
  predicates or sort descriptors.
- CloudKit encrypts these values on device. With Advanced Data Protection, keys
  are available only to the record owner and share participants.

## Lorvex Mapping

All Lorvex wire fields are written through `encryptedValues`, and the text
schema declares all seven as encrypted strings. Inbound sync uses custom-zone
change tokens instead of queries, so the no-index restriction is not a problem.

The decoder's plaintext fallback is migration compatibility, not permission to
ship a plaintext production schema. The first production schema deployment is
therefore the point of no return: verify the live field types before promotion.

“Encrypted field” is the unconditional platform guarantee. Full end-to-end
key exclusivity depends on the user's Advanced Data Protection setting; see
[ICLOUD_DATA_SECURITY.md](ICLOUD_DATA_SECURITY.md). Record IDs and system
metadata are also outside the encrypted field-value set; see
[CLOUDKIT_RECORD_ID.md](CLOUDKIT_RECORD_ID.md).

## Audit Conclusion

The current single encrypted-envelope layout is the preferred durable design.
Avoid adding CloudKit fields for domain-model evolution; use versioned encrypted
payloads unless a server-visible field is genuinely required.
