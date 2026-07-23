# CKContainer and the Production Environment

Source: [CKContainer](https://developer.apple.com/documentation/cloudkit/ckcontainer)

Last verified: 2026-07-10

## Apple Contract

- CloudKit selects Development or Production from the signed app's iCloud
  container environment entitlement/provisioning.
- App Store builds use production.
- Production rejects unknown record types and fields.
- Apple explicitly recommends testing production behavior before shipping.
- Simulator testing is development-only; use a physical device for production.

## Lorvex Mapping

Repository plist/entitlement validation cannot substitute for a signed-device
test. The release candidate must prove its embedded provisioning profile,
effective entitlements, CloudKit schema, account gate, custom zone, subscription,
encrypted record save, peer pull, and deletion pause against Production.

## Release Gate

Use two physical devices signed into the same test iCloud account and the exact
archive intended for TestFlight/App Store. Record effective entitlements with
`codesign`, create/update/delete representative large and aggregate entities,
exercise a cold background notification, reinstall/restore one device, and
confirm convergence without resetting the production container.
