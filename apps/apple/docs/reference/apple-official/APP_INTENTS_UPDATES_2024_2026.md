# App Intents Updates, 2024–2026

Source: [App Intents updates](https://developer.apple.com/documentation/updates/appintents)

Last verified: 2026-07-10

## Apple Direction

Apple's recent App Intents direction includes:

- app-schema conformance so Apple Intelligence can reason about well-known
  actions and entity shapes;
- `IndexedEntity` and `IndexedEntityQuery` for typed Spotlight content;
- interactive result and confirmation snippets;
- OS 26 execution modes that replace `openAppWhenRun`;
- OS 27 `SyncableEntity` for identifiers that remain stable across devices;
- entity ownership and confirmation concepts for sensitive/destructive actions.

## Lorvex Mapping

Lorvex already has a broad surface: 99 App Intent types and ten AppEntity
types. None currently adopts an app schema, `IndexedEntity`, `SyncableEntity`,
or an Assistant/AppIntent schema macro.

The entities' identifiers are generally the same stable identifiers carried by
SQLite and CloudKit, so `SyncableEntity` is a plausible future fit after its OS
27 contract is validated. Tasks, lists, habits, calendar events, and memory may
also benefit from typed Spotlight indexing or an applicable Reminders/Calendar/
Assistant schema.

This work must not precede the authorization findings. Making content easier
for Siri and Apple Intelligence to discover would amplify Lorvex's current
default-locked execution, no-confirmation, and Spotlight protection gaps.

## Safe Sequence

1. Classify authentication, discoverability, execution mode, and confirmation
   for every intent.
2. Protect and minimize the Spotlight corpus.
3. Unify AppEntity and Spotlight identity/mapping.
4. Adopt only schemas whose semantics exactly match Lorvex behavior.
5. Add interactive snippets for a small set of safe, routine actions.
6. Probe `SyncableEntity` and newer OS 27 APIs under Xcode 27 without making a
   beta SDK part of the first-release contract.

WWDC26 now includes a directly relevant Reminders schema domain, view
annotations, and `AppIntentsTesting`. Their proposed mapping to Lorvex tasks,
lists, calendar, and search is documented in
[WWDC26_INTELLIGENCE_PRODUCT_OPPORTUNITIES.md](WWDC26_INTELLIGENCE_PRODUCT_OPPORTUNITIES.md).
