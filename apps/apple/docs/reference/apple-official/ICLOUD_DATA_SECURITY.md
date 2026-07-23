# iCloud Data Security Overview

Source: [iCloud data security overview](https://support.apple.com/102651)

Last verified: 2026-07-10

## Apple Contract

Apple distinguishes two protection modes:

- Standard Data Protection encrypts iCloud data in transit and at rest, while
  Apple retains protected key material that can support account/data recovery.
- With Advanced Data Protection enabled, third-party CloudKit encrypted fields
  and assets receive end-to-end protection whose keys are available only to
  the user's trusted devices.

Some iCloud metadata remains outside that end-to-end boundary even with
Advanced Data Protection.

## Lorvex Mapping

`PRIVACY.md` and the bundled privacy summary already describe this distinction
accurately. They should remain the authority for user-facing language.

Several implementation comments, tests, and `SURFACE_DESIGN.md` call every use
of `CKRecord.encryptedValues` “end-to-end encrypted” without the Advanced Data
Protection qualifier. Those statements do not change runtime security, but
they blur encryption-at-rest with the stronger claim that Apple cannot access
key material. Use “encrypted CloudKit field” as the unconditional term and
reserve “end-to-end” for the ADP case.

