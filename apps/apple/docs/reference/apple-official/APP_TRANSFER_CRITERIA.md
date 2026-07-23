# App Transfer Criteria

Source: [App transfer criteria](https://developer.apple.com/help/app-store-connect/transfer-an-app/app-transfer-criteria/)

Last verified: 2026-07-10

## Apple Contract

Apple states that a Mac app that has used the sandbox environment and shares an
Application Group Container Directory with other Mac apps cannot be transferred.
This is an App Store Connect ownership constraint, not merely a signing step at
the moment of transfer.

Apple's transfer overview separately warns that transferring an app that shares
a CloudKit container can affect the other apps on the transferor's account.

## Lorvex Mapping

The MAS architecture includes at least two separately identified sandboxed Mac
app bundles:

- the main `Lorvex.app`; and
- `LorvexMCPHost.app` under `Contents/Helpers`.

Both claim the Lorvex App Group so they can open the same managed SQLite store.
They use distinct explicit bundle/App IDs and provisioning profiles. This likely
satisfies the condition Apple describes as sharing a group container with
another Mac app, but final interpretation should be confirmed against the actual
Developer Portal/App Store Connect identifiers before first release.

The same CloudKit container is also intentionally shared by the iPhone, Mac, and
other Lorvex targets, so a future cross-team transfer has data-access
consequences even if App Store Connect permits a particular platform record to
move.

## Irreversible Decision

If future sale, spin-out, or movement to another developer organization matters,
treat this as a pre-release architecture decision. Apple's wording applies to
apps that “have used” the configuration; removing the helper or App Group from a
later version may not restore transfer eligibility.

If the current same-group helper architecture is retained, record explicit owner
acceptance that app transfer may be unavailable and keep developer membership,
Team ID, App Group, and CloudKit container continuity as long-lived product
dependencies.
