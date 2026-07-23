# Core Spotlight Data Protection and Entity Indexing

Primary sources:

- [CSSearchableIndex.default](https://developer.apple.com/documentation/corespotlight/cssearchableindex/default%28%29)
- [CSSearchableIndex.init(name:protectionClass:)](https://developer.apple.com/documentation/corespotlight/cssearchableindex/init%28name%3Aprotectionclass%3A%29)
- [Core Spotlight protection classes](https://developer.apple.com/documentation/corespotlight/cssearchquery/protectionclasses)
- [Data Protection entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.default-data-protection)
- [Making app entities available in Spotlight](https://developer.apple.com/documentation/appintents/making-app-entities-available-in-spotlight)

Last verified: 2026-07-10

## Apple Contract

Apple's documentation says the default searchable index does not protect data
or support batch updates and should be used only while prototyping or testing a
Spotlight integration.

Named indexes support deliberate protection-class selection where the platform
supports it. File protection can make indexed data available only while the
device is unlocked, or after the first unlock. The app's default data-protection
entitlement participates in the platform default.

For apps that already model content as App Intents entities, Apple recommends
`IndexedEntity` or associating the entity with an existing searchable item. This
lets Spotlight and Siri refer to the same typed object instead of an unrelated
identifier/string document.

## Lorvex Mapping

The macOS bootstrap installs production indexers that call
`CSSearchableIndex.default()` for every delete and insert. No Lorvex entitlement
declares a default data-protection class, and there is no Spotlight setting or
opt-in.

The index is not limited to titles. It includes:

- task titles, notes, assistant-only notes, checklist text, tags, state, and due
  date;
- list names and descriptions;
- habit names and cues;
- daily-review title and summary;
- calendar-event title, time, location, provider/source, type, and timezone.

Several fields can contain health, employment, relationship, travel, or other
sensitive information. The user guide only describes searching task titles, so
the actual indexed scope is not discoverable from product copy.

The exact effective at-rest and lock-state behavior must be verified on the
shipping macOS archive. The stronger, already-proven conclusion is that the
code selects an index Apple explicitly says is not a production data-protection
design.

## Reliability and Integration Gaps

- Every refresh deletes an entire domain and then indexes its replacement. If
  the second operation fails, the domain stays empty until a later refresh.
- The default index cannot use the modern batch/client-state recovery API.
- Lorvex separately defines ten AppEntity types but associates none with the
  five Spotlight document types. Siri/semantic search cannot use the existing
  typed entity work through these items.
- Only the macOS bootstrap installs a real indexer. Mobile has handlers for a
  Spotlight result but no code that donates Lorvex content; the user guide's
  promise that task-title results appear in iOS Search is not implemented.

## Pre-Release Direction

1. Decide which fields are appropriate for system indexing. Default to the
   smallest useful set and make indexing/purge behavior user-visible.
2. Replace the default index with a named production index and deliberately set
   or verify its effective protection behavior in each signed artifact.
3. Use atomic/batched or incremental updates so a failed reindex does not erase
   the last good search corpus.
4. Unify Spotlight documents with AppEntity models using `IndexedEntity` or
   `associateAppEntity` on the macOS 15/iOS 18 generation.
5. Either implement iOS donation or remove the iOS Search promise and unused
   continuation path.
6. Test indexing, result visibility, purge, device lock, account switch,
   database reset, and uninstall on physical devices.

This can be corrected without changing the SQLite or CloudKit schemas.
