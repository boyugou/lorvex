# Providing User Access to CloudKit Data

Source: [Providing user access to CloudKit data](https://developer.apple.com/documentation/cloudkit/providing-user-access-to-cloudkit-data)

Last verified: 2026-07-10
Lorvex mapping updated: 2026-07-17

## Apple Contract

CloudKit user data belongs to the user. Apps integrating CloudKit need a way for
the user to view and export it. Apple permits an app that maintains a complete
on-device mirror through subscriptions to generate the report from that local
copy instead of querying CloudKit directly.

## Lorvex Mapping

- Native screens provide a view of the locally mirrored planner data.
- The category-based JSON/CSV/ZIP export uses the local application model and
  includes the current memory entries (a last-write key→value store).
- Both macOS and mobile expose deletion of Lorvex's CloudKit zone/data and pause
  sync to prevent immediate re-upload without explicit re-enable.

There is no single demonstrably complete portability artifact:

- category export omits `ai_changelog`, including the stored before/after and
  task-deferral audit history;
- the removed cross-app migration/full-backup flow is no longer a product
  contract; the current version-1 Apple export deliberately carries final planner
  state rather than a complete CloudKit account dump; and
- a local export does not include opaque future envelopes retained in
  `sync_pending_inbox`, persistent corrupt-record fences, or other transport
  state, nor prove that a terminal CloudKit drain completed immediately before
  export. The terminal drain performed before a *live import* protects import
  collision decisions; it does not make an earlier export a complete cloud
  snapshot.

## Release Check

Keep release and marketing copy scoped to a user-selected final-state backup,
not a complete CloudKit export. Verify coverage against the canonical syncable-
entity inventory and user-visible history surfaces, not a hand-maintained
category list. Any future claim of complete CloudKit export would additionally
require an export-side bounded terminal drain, explicit pending/corrupt-debt
handling, visible standing sync errors/pauses, and a representation for opaque
future envelopes.
