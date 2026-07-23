# Apple Official Reference Notes

These notes summarize Apple primary sources that constrain Lorvex's Apple
release, CloudKit protocol, privacy posture, and background behavior. They are
review aids, not mirrors of Apple's pages and not substitutes for checking the
live documentation before a release.

- Last source verification: 2026-07-10
- Code snapshot used for the latest Lorvex mapping pass: `605c8a6231605227334ab0f222a925b7f38a5aa5`
- Source policy: Apple Developer Documentation, App Store Review Guidelines,
  App Store Connect Help, and Apple Support security/privacy documentation only
- Copyright policy: paraphrases and short facts only; follow the source link for
  the complete, current text

## Page Notes

| Apple page | Local note | Main Lorvex relevance |
| --- | --- | --- |
| App Review Guidelines | [APP_REVIEW_GUIDELINES.md](APP_REVIEW_GUIDELINES.md) | MAS sandbox, background work, privacy, third-party AI |
| Upcoming Requirements | [APP_STORE_UPCOMING_REQUIREMENTS.md](APP_STORE_UPCOMING_REQUIREMENTS.md) | Required SDK, age-rating, quarantine gates |
| App privacy details | [APP_PRIVACY_DETAILS.md](APP_PRIVACY_DETAILS.md) | App Store Connect privacy answers |
| Privacy manifest files | [PRIVACY_MANIFEST_FILES.md](PRIVACY_MANIFEST_FILES.md) | Archive-level manifest verification |
| MetricKit | [METRICKIT.md](METRICKIT.md) | Local diagnostics and 2026 API transition |
| App crash reports | [APP_CRASH_REPORTS.md](APP_CRASH_REPORTS.md) | OS/App Store diagnostic channel versus Lorvex upload |
| Apple analytics sharing | [APPLE_ANALYTICS_SHARING.md](APPLE_ANALYTICS_SHARING.md) | User-controlled Apple diagnostic sharing |
| App Store Support URL | [APP_STORE_SUPPORT_URL.md](APP_STORE_SUPPORT_URL.md) | Public support page versus private review / DSA contact fields |
| Creating a widget extension | [WIDGET_SENSITIVE_CONTENT.md](WIDGET_SENSITIVE_CONTENT.md) | Lock Screen/Always-On sensitive-content redaction |
| App Intent authentication | [APP_INTENT_AUTHENTICATION.md](APP_INTENT_AUTHENTICATION.md) | Locked-device authorization for Siri/Shortcuts/widgets |
| App Intent confirmation | [APP_INTENT_CONFIRMATION.md](APP_INTENT_CONFIRMATION.md) | Confirmation before destructive/unsafe actions |
| App Intent execution modes | [APP_INTENT_EXECUTION_MODES.md](APP_INTENT_EXECUTION_MODES.md) | Deprecated `openAppWhenRun` migration |
| App Intents updates | [APP_INTENTS_UPDATES_2024_2026.md](APP_INTENTS_UPDATES_2024_2026.md) | App schemas, indexed entities, snippets, future sync identity |
| Core Spotlight protection | [CORE_SPOTLIGHT_DATA_PROTECTION.md](CORE_SPOTLIGHT_DATA_PROTECTION.md) | Named indexes, protection class, atomic reindexing |
| EventKit calendar sources | [EVENTKIT_CALENDAR_SOURCES.md](EVENTKIT_CALENDAR_SOURCES.md) | Provider-backed calendar write/sync disclosure |
| Pushing background updates | [BACKGROUND_PUSH_UPDATES.md](BACKGROUND_PUSH_UPDATES.md) | Silent-push delivery and 30-second budget |
| CKDatabaseSubscription | [CLOUDKIT_DATABASE_SUBSCRIPTION.md](CLOUDKIT_DATABASE_SUBSCRIPTION.md) | Subscription install, coalescing, change tokens |
| TN3162 CloudKit throttles | [CLOUDKIT_THROTTLES.md](CLOUDKIT_THROTTLES.md) | `retryAfterSeconds` and request pacing |
| Deploying a CloudKit schema | [CLOUDKIT_SCHEMA_DEPLOYMENT.md](CLOUDKIT_SCHEMA_DEPLOYMENT.md) | Irreversible production schema |
| Text-based CloudKit schema | [CLOUDKIT_TEXT_SCHEMA.md](CLOUDKIT_TEXT_SCHEMA.md) | Repository schema authority and validation |
| CKRecord encrypted values | [CLOUDKIT_ENCRYPTED_VALUES.md](CLOUDKIT_ENCRYPTED_VALUES.md) | Encryption cannot be retrofitted |
| Encrypting CloudKit user data | [CLOUDKIT_ENCRYPTING_USER_DATA.md](CLOUDKIT_ENCRYPTING_USER_DATA.md) | Key-reset recovery and deletion semantics |
| CKRecord.ID | [CLOUDKIT_RECORD_ID.md](CLOUDKIT_RECORD_ID.md) | Record-name metadata and deterministic hashes |
| iCloud data security | [ICLOUD_DATA_SECURITY.md](ICLOUD_DATA_SECURITY.md) | Standard protection versus ADP end-to-end encryption |
| CKError limit exceeded | [CLOUDKIT_LIMIT_EXCEEDED.md](CLOUDKIT_LIMIT_EXCEEDED.md) | 400-item/2-MB request guidance |
| CKRecord | [CLOUDKIT_RECORD.md](CLOUDKIT_RECORD.md) | 1-MB record limit and system-field cache |
| Optimizing iCloud Backup | [ICLOUD_BACKUP.md](ICLOUD_BACKUP.md) | Backup classification of local sync state |
| CKContainer | [CLOUDKIT_PRODUCTION_ENVIRONMENT.md](CLOUDKIT_PRODUCTION_ENVIRONMENT.md) | Production entitlement and on-device test |
| App Store provisioning profile | [APP_STORE_PROVISIONING_PROFILE.md](APP_STORE_PROVISIONING_PROFILE.md) | Explicit App IDs and per-bundle signing |
| App transfer criteria | [APP_TRANSFER_CRITERIA.md](APP_TRANSFER_CRITERIA.md) | Irreversible Mac App Group ownership constraint |
| User access to CloudKit data | [CLOUDKIT_USER_DATA_ACCESS.md](CLOUDKIT_USER_DATA_ACCESS.md) | View, export, and delete controls |
| Local preference registry (source audit) | [LOCAL_PREFERENCE_REGISTRY_AUDIT.md](LOCAL_PREFERENCE_REGISTRY_AUDIT.md) | No-op keys and future value-compatibility debt |
| Apple API deprecation audit | [APPLE_API_DEPRECATION_AUDIT.md](APPLE_API_DEPRECATION_AUDIT.md) | Current shipping deprecated calls and release gate |
| Deployment-target decision | [DEPLOYMENT_TARGET_DECISION.md](DEPLOYMENT_TARGET_DECISION.md) | Xcode 26 SDK with 15/18/11/2 minimums |
| Apple silicon and macOS 26 | [APPLE_SILICON_MACOS_26.md](APPLE_SILICON_MACOS_26.md) | Architecture and OS version are independent axes |
| macOS 26 release notes | [MACOS_26_RELEASE_NOTES.md](MACOS_26_RELEASE_NOTES.md) | Relevant platform changes and deprecations |
| Swift 6.2 modernization | [SWIFT_6_2_MODERNIZATION.md](SWIFT_6_2_MODERNIZATION.md) | Concurrency simplification without schema change |
| Apple localization architecture | [APPLE_LOCALIZATION_ARCHITECTURE_AUDIT.md](APPLE_LOCALIZATION_ARCHITECTURE_AUDIT.md) | Catalog coverage, bundle correctness, plural/runtime and translation-quality gaps |
| Apple notification and reminder audit | [APPLE_NOTIFICATION_REMINDER_AUDIT.md](APPLE_NOTIFICATION_REMINDER_AUDIT.md) | Delivery truth, rolling windows, concurrency, timezone/DST, and failure recovery |
| Apple external entrypoint routing audit | [APPLE_EXTERNAL_ENTRYPOINT_ROUTING_AUDIT.md](APPLE_EXTERNAL_ENTRYPOINT_ROUTING_AUDIT.md) | URL, notification-tap, Handoff, Spotlight, and quick-action route parity and validation |
| Apple database, bookmark, and MCP trust audit | [APPLE_DATABASE_BOOKMARK_MCP_TRUST_AUDIT.md](APPLE_DATABASE_BOOKMARK_MCP_TRUST_AUDIT.md) | Historical: audits the removed external-DB/bookmark switching. Its App Group composition and MCP helper-trust analysis still describes the current single managed-store boundary |
| Apple import/export archive safety audit | [APPLE_IMPORT_EXPORT_ARCHIVE_SAFETY_AUDIT.md](APPLE_IMPORT_EXPORT_ARCHIVE_SAFETY_AUDIT.md) | Historical 2026-07-10 audit with a current-status header covering the version-1 format and terminal CloudKit import boundary |
| Apple accessibility matrix audit | [APPLE_ACCESSIBILITY_MATRIX_AUDIT.md](APPLE_ACCESSIBILITY_MATRIX_AUDIT.md) | VoiceOver and keyboard action parity, Larger Text, hit regions, visual semantics, adaptive settings, focus, and App Store nutrition-label evidence |
| Apple lifecycle, restoration, and time audit | [APPLE_LIFECYCLE_RESTORATION_TIME_AUDIT.md](APPLE_LIFECYCLE_RESTORATION_TIME_AUDIT.md) | Cold/warm launch, termination and drafts, window/scene ownership, atomic database cutover, restoration, midnight/time-zone changes, and memory pressure |
| Apple signed-release performance and MetricKit audit | [APPLE_SIGNED_RELEASE_PERFORMANCE_METRICKIT_AUDIT.md](APPLE_SIGNED_RELEASE_PERFORMANCE_METRICKIT_AUDIT.md) | First local usability, refresh fan-out, background leases, MetricKit coverage/deprecation, resource budgets, signposts, benchmarks, and exact-artifact evidence |
| Apple finalization audit coverage map | [APPLE_AUDIT_COVERAGE_MAP.md](APPLE_AUDIT_COVERAGE_MAP.md) | Reviewed areas, partial coverage, and the highest-value remaining audits |
| macOS App Group provisioning | [MACOS_APP_GROUP_PROVISIONING.md](MACOS_APP_GROUP_PROVISIONING.md) | Final signed entitlement/profile/runtime proof |
| Notarization distribution | [NOTARIZATION_DISTRIBUTION.md](NOTARIZATION_DISTRIBUTION.md) | Stapling the artifact users actually download |
| Foundation Models, 2025–2026 | [FOUNDATION_MODELS_2025_2026.md](FOUNDATION_MODELS_2025_2026.md) | Optional on-device AI and model-version contract |
| WWDC26 intelligence product opportunities | [WWDC26_INTELLIGENCE_PRODUCT_OPPORTUNITIES.md](WWDC26_INTELLIGENCE_PRODUCT_OPPORTUNITIES.md) | Siri AI, Reminders schemas, view annotations, structured multimodal capture, Spotlight RAG, PCC, evaluations, and a staged Lorvex roadmap |
| Apple multi-OS versioning and App Store routing | [APPLE_MULTI_OS_VERSIONING_AND_APP_STORE_ROUTING.md](APPLE_MULTI_OS_VERSIONING_AND_APP_STORE_ROUTING.md) | SDK versus deployment target, availability adapters, app thinning, last-compatible builds, and cross-version data safety |
| AlarmKit, 2025 | [ALARMKIT_2025.md](ALARMKIT_2025.md) | Narrow opt-in timer/alarm use case |
| Continuous background processing, 2025 | [BACKGROUND_CONTINUED_PROCESSING_2025.md](BACKGROUND_CONTINUED_PROCESSING_2025.md) | User-started long-running work, not silent-push escape |

## Document-Driven Review Output

[NEW_FINDINGS.md](NEW_FINDINGS.md) records only findings newly derived in this
documentation pass. It deliberately does not duplicate the older audit backlog.

The highest-value new checks are:

1. Inspect per-subscription results instead of treating a successful outer
   CloudKit request as a successful subscription save.
2. Give the iOS silent-push path a deadline shorter than Apple's 30-second
   execution budget.
3. Preserve CloudKit's server-provided retry interval through every error path.
4. Separate reconstructible CloudKit cache files from account/deletion consent
   state before choosing backup behavior.
5. Exercise the production CloudKit environment on physical devices before
   TestFlight/App Store submission.
6. Preserve the documented decision that deterministic low-entropy record names
   expose bounded, dictionary-testable metadata; they are not a secrecy boundary.
7. Implement and test Apple's encrypted-key-reset recovery discriminator.
8. Verify redaction of every user-authored widget/control/complication field
   while the device is locked.
9. Assign an explicit authentication and discoverability policy to every App
   Intent; do not inherit the framework's locked-device default accidentally.
10. Remove, reject, or fully specify every preference key that currently has no
    Apple behavior before calling the data contract frozen.
11. Require confirmation before destructive App Intents mutate the synced
    database, independently of their authentication policy.
12. Make privacy copy describe EventKit write-back to iCloud/CalDAV/Exchange or
    another user-selected Calendar provider, not only the local API call.
13. Replace the all-intent `openAppWhenRun` dependency with explicit modern
    execution modes while preserving the deployment floor.
14. Prove that every real signed Mac process has profile-authorized, OS-
    validated App Group entitlements; embedding profiles is not that proof.
15. Repackage and validate the actual downloadable ZIP after stapling the
    accepted app.
16. Treat the finite tombstone lifetime and zone-rebuild epoch as a sync-
    protocol freeze decision, not an ordinary cleanup constant.

## Maintenance Rule

When a source is rechecked, update its individual note's verification date and
the index above. If Apple changes a contract, record the old and new behavior in
the page note before changing code or release policy.
