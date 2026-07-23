# New Findings from Apple Documentation Pass

Scope: findings newly derived from Apple primary sources on 2026-07-10 and
revalidated against `main` at `cd2b10f0e`. This file does not repeat the prior
audit backlog and contains no implementation changes.

## F1 — Subscription Save Can Fail Per Item but Be Recorded as Installed

Severity: Medium  
Confidence: High

Apple's async subscription API returns per-subscription `Result` values even when
the outer request succeeds. `CloudKitCloudSyncSubscriber.registerSubscription()`
discards that result tuple at
`Sources/LorvexCloudSync/CloudSyncSubscriptionManager.swift:54`, then macOS and
mobile set `hasRegisteredSubscription = true`.

Impact: a production-schema/configuration/per-item failure can silently disable
remote notifications for the rest of the process session. Foreground refresh is
still a convergence backstop, so this is not necessarily permanent data loss.

Required verification: inject a successful outer response containing a failed
save result and require the caller to remain retryable and expose the error.

Primary source: [CKDatabase.modifySubscriptions](https://developer.apple.com/documentation/cloudkit/ckdatabase/modifysubscriptions%28saving%3Adeleting%3A%29)

## F2 — Silent-Push Work Has No 30-Second Deadline

Severity: Medium  
Confidence: High

`LorvexMobileAppDelegate` awaits `handleCloudKitRemoteChange()`, which awaits a
full refresh. One wake can drain 64 pages and then perform the ordinary snapshot,
widget, reminder, and badge fan-out. It can also wait for an existing refresh and
its coalesced rerun. There is no timeout or durable “remaining work” handoff for
an attached store.

Impact: iOS can terminate the app before it calls the completion handler and may
throttle future background delivery.

Primary source: [Pushing background updates to your app](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)

## F3 — CloudKit Server Retry Deadlines Are Lost

Severity: Medium  
Confidence: High

The local pacing system uses a generic exponential delay, but no path reads or
propagates `CKError.retryAfterSeconds`. Push failures often become strings and
bits before reaching pacing; subscription retries are outside that gate. iOS
push receipt resets local pacing unconditionally.

Impact: Lorvex can retry while CloudKit is still rejecting requests, extending
throttling, increasing battery/network use, and delaying convergence.

Primary source: [TN3162: Understanding CloudKit throttles](https://developer.apple.com/documentation/technotes/tn3162-understanding-cloudkit-throttles)

## F4 — CloudKit Cache and Consent State Share One Backup Lifecycle

Severity: Medium  
Confidence: Medium; needs restore testing

`CloudSyncCheckpoints` mixes reconstructible change tokens/system fields with the
account fingerprint and fail-closed pause reason. Application Support is backed
up by default, and no exclusion metadata is set. On iOS, the managed database and
checkpoint directory also live in different containers.

Impact: a restored checkpoint can be newer than the restored database and skip
changes the database never saw. Excluding the entire directory could instead
drop a user-deleted-zone consent gate.

Resolution (2026-07-16): closed. Change tokens now live only in the managed
SQLite traversal state and commit atomically with each inbound page. The renamed
`CloudSyncState/Cache` contains only reconstructible CKRecord system fields and
is backup-excluded; revisioned account/consent files remain in the parent.

Primary source: [Optimizing your app's data for iCloud Backup](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup)

## F5 — Third-Party AI Review Language Should Say “Share/Access”

Severity: Low review risk  
Confidence: Medium

The Assistant settings provide a strong disclosure and the setup flow is
affirmative. The privacy policy's repeated “Lorvex never transmits” framing may
nevertheless sound narrower than Apple's requirement to disclose sharing with
third-party AI. Review Notes should describe the actual access plainly.

Impact: avoidable privacy-question/review friction, not a demonstrated runtime
violation.

Primary source: [App Review Guidelines, 5.1.2](https://developer.apple.com/app-store/review/guidelines/#privacy)

## F6 — CI Does Not Prove the Required Xcode 26 Submission Toolchain

Severity: High release-gate gap  
Confidence: High

Apple has required Xcode 26 and version 26 SDKs for iOS/iPadOS/visionOS/watchOS
uploads since 2026-04-28. `.github/workflows/apple-ci.yml` runs `macos-15` without
selecting Xcode. The official runner inventory lists Xcode 16.4 as that image's
default even when Xcode 26 is also installed.

Impact: CI can be fully green under a compiler/SDK that cannot produce an
acceptable current iPhone, Watch, or Vision submission. API availability,
linking, generated metadata, and packaging behavior can differ in Xcode 26.

The current local machine has Xcode 26.6, so local release work can satisfy the
gate; the problem is absence of repeatable CI evidence.

Primary source: [Apple Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)

Runner evidence: [GitHub macOS 15 image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)

## F7 — MAS Packaging Does Not Assert Absence of Quarantine Attributes

Severity: Low implementation gap; hard upload failure if triggered  
Confidence: High

Apple rejects macOS uploads containing `com.apple.quarantine` anywhere in the
app. No packaging verifier currently searches for the attribute. The app bundles
present in `apps/apple/dist` were clean when inspected on 2026-07-10, so this is
a missing future-proof gate rather than a current contaminated artifact.

Primary source: [Apple Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)

## F8 — MetricKit's MX Subscriber API Entered Deprecation

Severity: Low maintenance  
Confidence: High

Apple's June 2026 MetricKit update replaces `MXMetricManager` with the
async-sequence `MetricManager` API on OS 27. Lorvex currently uses the MX
subscriber exclusively. Its iOS 17/macOS 14 floor requires a compatibility path,
so the correct future design is availability-gated dual support rather than an
immediate replacement.

Primary source: [MetricKit updates](https://developer.apple.com/documentation/updates/metrickit)

## F9 — “Full Backup” and Data-Portability Exports Have Different Holes

Severity: Medium  
Confidence: High

> **Superseded in part (2026-07-17).** The interchange/migration UI and its
> whole-setup/full-backup claim were removed. The current version-1 Apple export
> is documented as a final-state, user-selected backup rather than a complete
> CloudKit dump. The narrower completeness limitation below remains: it omits
> `ai_changelog`, pending/future transport rows, and persistent corrupt-record
> debt, and export itself does not establish a terminal CloudKit drain. The new
> same-gate terminal drain belongs to live *import* and must not be cited as
> export-completeness evidence.

The category JSON/CSV/ZIP export includes current planner entities, but has no
AI changelog category. The interchange/migration UI describes its archive as a
whole setup, complete file, and full backup, while the interchange denylist
explicitly excludes `ai_changelog`. The changelog also backs user-visible task
defer history.

Neither path represents forward-compatible CloudKit envelopes retained in
`sync_pending_inbox`, and export does not establish that a CloudKit drain
completed immediately before the local snapshot.

Impact: moving/restoring from the advertised full backup loses user-visible
AI/defer audit history. A user requesting a complete
copy of CloudKit-backed data has no one artifact whose completeness can be
demonstrated.

Primary source: [Providing user access to CloudKit data](https://developer.apple.com/documentation/cloudkit/providing-user-access-to-cloudkit-data)

## F10 — MAS App Group Architecture May Permanently Prevent App Transfer

Severity: Medium business/architecture constraint  
Confidence: Medium pending portal confirmation

Apple says a sandboxed Mac app that has used and shares an Application Group
Container Directory with other Mac apps cannot be transferred. Lorvex packages
the main app and a separately identified/provisioned sandboxed MCP helper app;
both join the same App Group.

Impact: after first MAS release, selling Lorvex or moving it to another developer
team/account may be impossible through App Store Connect. The shared CloudKit
container creates additional cross-platform transfer consequences.

This is not a reason to remove the App Group automatically: it is central to
multi-process database coherence. It is an irreversible tradeoff to accept or
redesign consciously before first release.

Primary source: [App transfer criteria](https://developer.apple.com/help/app-store-connect/transfer-an-app/app-transfer-criteria/)

## F11 — Unsalted Deterministic Record Names Leak Low-Entropy Metadata

Severity: Medium privacy/protocol-freeze decision  
Confidence: High

`CloudSyncEnvelopeRecord.recordName()` uses the unsalted SHA-256 of
`entity_type + NUL + entity_id`. `CKRecord.ID` is record metadata, not an
encrypted field. Dates are natural IDs for daily reviews/current focus/focus
schedules, and preference IDs come from a small fixed catalog. An observer can
therefore precompute those hashes and recognize type/date/preference presence
even though every custom field is encrypted.

Impact: payload content remains encrypted, but at discovery the code and text
schema claimed that the name disclosed neither type nor ID, which was false for
enumerable inputs. Changing record names after production requires a record
migration and deletion strategy, so accept-and-document versus
keyed-deterministic naming was a real pre-production decision.

Resolution: accepted and documented on 2026-07-15. Lorvex keeps the fixed-width
deterministic hash because a keyed namespace introduces a cross-device secret
bootstrap and loss/fork recovery contract. The source no longer describes the
hash as a secrecy boundary for low-entropy IDs.

Primary source: [CKRecord.ID](https://developer.apple.com/documentation/cloudkit/ckrecord/id)

Local analysis: [CLOUDKIT_RECORD_ID.md](CLOUDKIT_RECORD_ID.md)

## F12 — Encrypted-Key Reset Is Not Distinguished from Ordinary Missing Zone

Severity: Medium recovery gap  
Confidence: High that the discriminator is absent; production behavior needs an injected probe

Apple reports an iCloud Keychain encryption reset as `zoneNotFound` plus
`CKErrorUserDidResetEncryptedDataKey` and prescribes delete-zone, recreate-zone,
then local re-upload. Lorvex never reads that `userInfo` key. Its generic
`zoneNotFound` recovery is similar — it invalidates metadata, backfills,
recreates, and re-fetches — but omits the explicit reset-specific deletion,
diagnostic, and test.

Impact: the app has no evidence that it follows Apple's recovery contract for
the exact event most specific to its all-encrypted schema. A failure here can
wedge sync after the old encryption material becomes permanently unusable.

Primary source: [Encrypting User Data](https://developer.apple.com/documentation/cloudkit/encrypting-user-data)

## F13 — Internal “End-to-End” Claims Ignore the ADP Boundary

Severity: Low documentation/test terminology  
Confidence: High

The user-facing privacy policy correctly says standard iCloud protection keeps
recoverable key material with Apple and that CloudKit encrypted fields become
fully end-to-end protected with Advanced Data Protection. Several source
comments, test descriptions, and `SURFACE_DESIGN.md` instead equate every use of
`CKRecord.encryptedValues` with unconditional end-to-end encryption.

Impact: no runtime weakening, but the internal security contract is misstated
and can seed incorrect future product or review copy. Use “encrypted field”
unconditionally and qualify “end-to-end” by ADP.

Primary source: [iCloud data security overview](https://support.apple.com/102651)

## F14 — MetricKit Privacy Copy Overpromises About Apple's OS Channel

Severity: Medium privacy wording  
Confidence: High that the Apple channel exists; Medium on how reviewers read the current sentence

Lorvex does not upload its locally persisted MetricKit reports. However,
`PRIVACY.md` says those diagnostics are never transmitted anywhere, including
to Apple. Apple separately collects/shares crash reports according to the
user's Analytics settings, and TestFlight users automatically share crash
reports with the developer regardless of that ordinary setting.

Impact: the App Store “no developer collection” answer can still be correct,
but the public policy's categorical platform-wide promise is broader than the
app controls. Limit it to Lorvex's own local copy and acknowledge Apple's
separate OS/App Store behavior.

Primary source: [Acquiring crash reports and diagnostic logs](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)

Related source: [Share analytics, diagnostics, and usage information with Apple](https://support.apple.com/108971)

## F15 — Public Support URL Resolved; Account Contacts Remain External

Severity: Resolved in repository; account-level release actions remain
Confidence: High

Apple requires a Support URL and says it must lead to actual contact information;
Guideline 1.5 requires an easy way to contact the developer. Lorvex now uses the
public, login-free `https://lorvex.app/support/` page, so repository visibility
and GitHub authentication no longer affect the Support URL.

Remaining boundary: App Review Information still needs private phone/email
details supplied to Apple, and an EU trader declaration may require public legal
contact details on Apple's product page. Those are account/storefront inputs,
not a missing support-page implementation.

Primary source: [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)

Related source: [App Review Guidelines, 1.5](https://developer.apple.com/app-store/review/guidelines/#developer-information)

## F16 — Sensitive Widget Coverage Stops at Accessory Families

Severity: Medium privacy gap  
Confidence: High

Lorvex correctly marks task titles privacy-sensitive in its accessory-inline,
accessory-rectangular, and Watch rectangular/corner views. However, the
standard small/medium/large Focus and Today widgets still display task titles
and sometimes a user-authored briefing without the marker. The Focus Control
Widget also displays the first task title without marking its label or control
template. No extension-wide Data Protection entitlement supplies a fallback.

Impact: in Lock Screen, StandBy, Always-On, Mac-from-iPhone, CarPlay, or Control
surfaces, system privacy settings cannot reliably redact all user-authored
Lorvex text. A task title may contain health, work, relationship, or other
sensitive information.

Primary source: [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)

Local mapping: [WIDGET_SENSITIVE_CONTENT.md](WIDGET_SENSITIVE_CONTENT.md)

## F17 — Every Shipping App Intent Inherits Locked-Device Execution

Severity: High authorization/privacy gap  
Confidence: High

Apple's `AppIntent.authenticationPolicy` defaults to `.alwaysAllowed`, which
explicitly permits execution while the device is locked. Lorvex defines 93
system App Intents and six widget intents; none sets an authentication policy.
The system intents are linked into the macOS, iPhone/iPad, and visionOS apps,
default to discoverable, and their own provider documentation says they remain
invokable through Shortcuts and automations.

The surface is not limited to harmless capture: it can read memory/review/task/
calendar/preference/diagnostic content, return full data-export files, and
perform deletes and broad batch mutations against the real shared database.
There are no intent-level confirmation calls or a central locked-device gate.

Impact: Lorvex has delegated the authorization decision for its broadest
external read/write surface to a framework default intended to be overridden
for protected operations. Depending on system invocation paths and user
settings, locked-device Siri, shortcuts, automations, controls, or companion
devices may disclose or change private planner data without local unlock.

This requires an explicit per-capability policy before release: at minimum
exports and sensitive reads should require local-device authentication, while
destructive/broad writes should require authentication unless a narrowly
documented locked workflow justifies otherwise. Widget-only intents should also
be reviewed for `isDiscoverable = false`.

Primary source: [AppIntent.authenticationPolicy](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy)

Local mapping: [APP_INTENT_AUTHENTICATION.md](APP_INTENT_AUTHENTICATION.md)

## F18 — Canonical Preference Allowlist Accepts 26 No-Behavior Keys

Severity: Medium data-contract/product-semantics debt  
Confidence: High for the absence of shipping Swift consumers

The Apple preference registry contains 38 canonical keys. Twenty-six have no
shipping Swift reference outside the registry itself, yet the generic system
intent/MCP preference writers accept them and most can sync through CloudKit.
Examples include `memory_lock_enabled`, `widget_hide_titles`, quiet hours,
notification sound/muted lists, font scale, dashboard layout, and focus-window
confirmation behavior.

Impact: writes report success while no Apple feature changes. Security/privacy
names can create false expectations. More importantly for schema freeze, an
arbitrary JSON value accepted and synced today becomes legacy input that a
future implementation must parse or migrate. These keys do not need to be
pre-reserved because the generic preference envelope can add a new key without
changing SQLite or CloudKit schema.

Before release, classify every registry-only key as implemented with typed
validation, rejected until implemented, or explicitly reserved but not
writable/syncable. Do not let the current allowlist accidentally become the
permanent data contract.

Local analysis: [LOCAL_PREFERENCE_REGISTRY_AUDIT.md](LOCAL_PREFERENCE_REGISTRY_AUDIT.md)

## F19 — Destructive App Intents Mutate Before Any Confirmation

Severity: Medium-High data-integrity gap  
Confidence: High

Apple provides `requestConfirmation()` for destructive or unsafe App Intent
work. Lorvex calls no confirmation API anywhere in its App Intent modules.
Custom delete/cancel/reset/remove intents proceed directly to the real database
and show only an after-the-fact success dialog. Several operations emit
CloudKit tombstones, spreading an accidental action to peers.

Impact: authentication would address the locked-device problem in F17 but
would not protect an unlocked user from Siri ambiguity, a mistaken entity
selection, or an unexpectedly destructive shortcut/automation. Confirmation
must happen before the first mutation, with any unattended-automation exception
made explicit and tested.

Primary source: [AppIntent.requestConfirmation()](https://developer.apple.com/documentation/appintents/appintent/requestconfirmation%28%29)

Local mapping: [APP_INTENT_CONFIRMATION.md](APP_INTENT_CONFIRMATION.md)

## F20 — EventKit Privacy Copy Denies the Sync Path the Code Prefers

Severity: Medium privacy-policy mismatch  
Confidence: High

`PRIVACY.md` calls Calendar access local to the device and says calendar data is
not transmitted except through Lorvex CloudKit or MCP. The macOS EventKit
adapter explicitly prefers an iCloud/CalDAV calendar source so its dedicated
Lorvex calendar syncs across devices. It writes event title, time, location,
notes/marker, and recurrence data; users can also select another provider-
backed writable calendar such as Exchange.

Impact: the feature is permissioned and reasonable, and Lorvex does not run the
calendar provider. But the provider/system can sync exactly the data the policy
says stays on device. Update the policy and in-app summary to explain that
write-back is governed by the chosen Calendar account/provider and may leave
the device. Re-evaluate App Store privacy answers explicitly rather than
assuming “EventKit API call is local” proves the result remains local.

Primary source: [EKSource](https://developer.apple.com/documentation/eventkit/eksource)

Local mapping: [EVENTKIT_CALENDAR_SOURCES.md](EVENTKIT_CALENDAR_SOURCES.md)

## F21 — All 99 App Intents Use the Deprecated Execution Boolean

Severity: Medium platform-maintenance debt

Confidence: High

Apple has deprecated `openAppWhenRun` in favor of `supportedModes`, which can
express background, immediate foreground, dynamic, and deferred transitions.
Every Lorvex App Intent declares the old Boolean and none declares the modern
mode API.

Impact: current deployment targets still need compatibility, so this is not an
immediate release blocker. Leaving the migration until a future required SDK
raises warning/build and behavioral risk across 99 intents at once. Fold it
into the F17/F19 intent classification instead of performing a blind mechanical
replacement.

Primary source: [AppIntent.openAppWhenRun](https://developer.apple.com/documentation/appintents/appintent/openappwhenrun)

Local mapping: [APP_INTENT_EXECUTION_MODES.md](APP_INTENT_EXECUTION_MODES.md)

## F22 — Production Spotlight Uses Apple's Prototype-Only Default Index

Severity: High privacy/release gap

Confidence: High

The macOS indexers call `CSSearchableIndex.default()` four times. Apple says the
default index does not provide data protection or batch-update support and is
for prototyping/testing; production content should use a named index with a
deliberate protection class.

Lorvex indexes task titles, notes, AI notes, checklist text, tags, list and habit
content, daily-review summaries, and calendar title/time/location/source data.
There is no default-data-protection entitlement supplying a fallback.

Impact: sensitive planner text is placed in a production search index whose
protection policy was never selected. Exact lock-state behavior must still be
verified on a signed device build, but using the prototype-only API for this
corpus is itself contrary to Apple's production guidance.

Primary source: [Making app entities available in Spotlight](https://developer.apple.com/documentation/appintents/making-app-entities-available-in-spotlight)

Local mapping: [CORE_SPOTLIGHT_DATA_PROTECTION.md](CORE_SPOTLIGHT_DATA_PROTECTION.md)

## F23 — The iOS Search Promise Has No iOS Indexing Producer

Severity: Medium product/documentation mismatch

Confidence: High

Only the macOS app constructs the real Spotlight indexers. The mobile target has
continuation/navigation handling but no corresponding content donation. The
user guide nevertheless promises iOS Search results and says mobile refresh
reindexes them.

Lorvex also has ten AppEntity types but does not associate those entities with
the five existing Spotlight document categories, adopt `IndexedEntity`, or
implement `IndexedEntityQuery` reindexing.

Impact: the advertised iOS behavior cannot occur, and the macOS index has two
unified identity systems that cannot yet support typed Spotlight/Siri opening.
Remove the promise or implement a protected iOS producer; do not broaden
discoverability until F17, F19, and F22 are closed.

Primary source: [Spotlight integration](https://developer.apple.com/documentation/appintents/spotlight)

## F24 — Three Already-Available Deprecation Migrations Remain

Severity: Medium release-maintenance gap

Confidence: High

The current source contains six uses of
`NSApplication.activate(ignoringOtherApps:)`, seven EventKit authorization
switches retaining deprecated `.authorized` beside `.fullAccess`, and three
SwiftUI `Text + Text` operations in the command-palette result renderer.

The AppKit replacement is available at Lorvex's existing macOS 14 floor;
EventKit's full/write-only model is the same macOS 14/iOS 17 generation; the
Text concatenation deprecation also exposes a localization-ordering problem.
These are separate from the 99-intent F21 migration.

Impact: known deprecated paths survive into a release built on Xcode 26 and the
current source-level gate does not reliably report them. Add a current-SDK
warnings/deprecation release gate after the migrations rather than suppressing
the warning categories.

Local mapping: [APPLE_API_DEPRECATION_AUDIT.md](APPLE_API_DEPRECATION_AUDIT.md)

## F25 — Mac Distribution Documentation Describes a Nonexistent Artifact

Severity: Medium release-operator risk

Confidence: High

Status: Resolved. The production direct-distribution path is now explicitly
arm64-only and emits `Lorvex-macOS-<version>+<build>-arm64.dmg`; current release
and distribution docs match that contract.

The audited `package_dmg.sh` was Apple-silicon-only, rejected non-arm64 slices,
had no `--host-arch` option, and produced an `-arm64.dmg`. XcodeGen also excludes
`x86_64`. `docs/DISTRIBUTION.md` and `docs/release.md` still describe a universal
default, a `--host-arch` mode, an `-universal.dmg`, and in places the wrong
staged executable name. The distribution guide also shows the old array form
of the CloudKit environment entitlement even though the signed entitlement was
corrected to a scalar.

Impact: the person performing the release can follow documentation that cannot
match the scripts or misdiagnose a correct arm64 artifact as incomplete. Align
the runbook with the chosen policy: arm64 default; universal only if a separate
secondary workflow is intentionally restored.

## F26 — Finite Tombstone GC Needs the Chosen Zone-Epoch Contract

Severity: High sync-protocol freeze blocker

Confidence: High

Plain tombstones can disappear after the active-device window, the fallback
retention is finite, and every tombstone is eventually removed. The local
device-cursor table is not a peer acknowledgement of this device's delete. If
an old live device returns after tombstone removal and a CloudKit-zone rebuild,
the empty zone contains no durable death fact and the stale live row can be
backfilled as new.

The finalization backlog has already selected a bounded 365-day recovery
contract plus a monotonic zone epoch and snapshot re-enrollment for an expired
or pre-epoch device. That direction is sound but is not implemented at this
snapshot.

Impact: without the epoch/re-enrollment rule, the existing code cannot promise
both finite retention and convergence for indefinitely offline devices. This
must be settled before calling the sync protocol frozen; it is not an ordinary
post-launch tuning constant.

## F27 — Release-Link Verification Can Destroy a Tracked User Edit

Severity: High local-safety gap

Confidence: High

`script/verify_release_link.sh` unconditionally runs
`git checkout -- core/Package.resolved` after `xcodebuild`. If that file was
legitimately dirty before the verifier began, the command silently discards the
user's edit. `archive_ios.sh` already uses a byte snapshot/restore pattern, but
the release-link verifier did not receive the same correction.

Impact: a read-looking verification command mutates and can destroy concurrent
work in exactly the shared-worktree scenario used during finalization. Do not
run it in a dirty tree until it preserves the caller's exact pre-run bytes.

## F28 — Generated Xcode Builds Do Not Enforce the Committed Resolution

Severity: Medium release-reproducibility gap

Confidence: High

The XcodeGen spec declares GRDB and swift-markdown using open-ended `from:`
ranges. Each generated project is placed in a gitignored distribution directory
and has no committed workspace `Package.resolved`. No wrapper seeds the outer
committed lock into that workspace or passes
`-onlyUsePackageVersionsFromResolvedFile` and
`-disableAutomaticPackageResolution`.

Impact: an App Store archive can resolve a dependency version that differs from
the reviewed pins, and the verifier's destructive checkout can erase evidence
that resolution changed. The outer lock contains the required pins, but the
generated workspace does not currently consume it as an enforced authority.

## F29 — App Store Packaging Does Not Require the Schema Freeze to Be Armed

Severity: Medium-High release-governance gap

Confidence: High

`schema/migration_policy.json` remains pre-launch with `launched: false` and no
frozen baseline. That is correct during development, and the verifier
intentionally no-ops in this state. The iOS and Mac App Store archive scripts do
not distinguish a private development archive from a public release candidate
or reject an unarmed policy.

Impact: the first public build can be packaged and uploaded while the permanent
schema baseline is still mutable simply because the operator forgot the manual
`--arm` step. Arming remains an owner action, but the public-release path should
make omission impossible or require an explicitly named pre-release override.

## F30 — Manual Mac Signing Lacks Final App-Group Validation Evidence

Severity: High release-evidence blocker

Confidence: High that the evidence is absent; final runtime outcome requires real profiles

Status: Resolved in production tooling; every actual release must still retain
the generated signed-candidate evidence. `package_dmg.sh` now requires three
explicit Developer ID profiles, derives the signed application/team identifiers
from them, strictly cross-checks profiles and final signatures, and executes a
real App Group helper write from the mounted/copied artifact. Main-app and
widget `launchctl procinfo` evidence remains an operator record.

Apple treats the executable's signed entitlements and the provisioning
profile's authorization as separate inputs. Xcode normally synthesizes final
entitlements from the project, account, and entitlement file. Lorvex manually
passes checked-in plists to `codesign` and embeds profiles; those plists contain
the App Group but not application/team identifiers.

The MAS verifier checks the profile App ID and compares profile capabilities to
the signed capability values. It does not require the signed executable's own
application/team identifier to match the profile or prove macOS marked the
running app, helper, and widget as `entitlements validated`.

The audited Developer ID route also soft-skipped profiles. On macOS 15+, an iOS-style
`group.*` container outside the Mac App Store needs profile authorization (or a
different Team-ID-prefixed group); without it the app may prompt temporarily
and an extension can be denied outright.

Impact: source checks can pass while the final profile-backed App Group remains
unproven. This is not a claim that every package must fail; it is a hard release
gate until a real signed candidate proves final entitlements, profile
authorization, system validation, and cross-process container access for all
three targets.

Primary sources: [Entitlements](https://developer.apple.com/documentation/bundleresources/entitlements), [Accessing app group containers](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)

Local mapping: [MACOS_APP_GROUP_PROVISIONING.md](MACOS_APP_GROUP_PROVISIONING.md)

## F31 — The Downloadable ZIP Is Created Before the App Is Stapled

Severity: Medium distribution-integrity gap

Confidence: High

Status: Resolved. The submit path now rebuilds the ZIP from the stapled app and
validates a clean extraction of the final downloadable artifact. The offline
preflight also validates the exact archived app rather than only its sibling in
`dist/`.

`archive_local.sh` creates the ZIP. `notarize_archive.sh --submit` submits that
ZIP, then staples and validates the separate `dist/Lorvex.app`. Apple's guidance
is to staple the item intended for distribution; for a ZIP this means packaging
the stapled app into the final downloadable ZIP.

The resolved failure mode was that notarization could succeed while the ZIP
offered to users still contained the pre-staple app. The current script rebuilds
and revalidates the exact downloadable artifact after acceptance.

Primary source: [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)

Local mapping: [NOTARIZATION_DISTRIBUTION.md](NOTARIZATION_DISTRIBUTION.md)

## F32 — macOS Duplicates the Mobile CloudSync Construction Graph

Severity: Low refactor/reliability debt

Confidence: High

Mobile constructs subscribers, coordinators, checkpoint directories, and mode
resolution through `CloudSyncFactory`. `AppCoreFactory` manually assembles the
same graph, and the shared factory comment explicitly leaves macOS convergence
for later.

Impact: every future checkpoint, pause-state, retry, account-gate, or zone-epoch
dependency must be wired correctly in two factories. This has already become a
sensitive protocol surface. Unifying construction is behavior-preserving and
does not require a data/schema migration, but it should follow focused factory
parity tests rather than a broad rewrite.

## F33 — Declared Deployment Floors Still Contradict the Chosen Policy

Severity: Medium release-configuration decision

Confidence: High

The agreed release direction is macOS 15, iOS/iPadOS 18, watchOS 11, and
visionOS 2, with Xcode 26 and OS-26 APIs availability-gated. The repository
still declares macOS 14, iOS 17, watchOS 10, and visionOS 1 across SwiftPM,
XcodeGen, metadata, and Info-plist sources.

Impact: the current build remains valid, but modernization work cannot safely
assume the selected floor and the release artifact may advertise a different
support contract from the owner decision. Change all version authorities
together and test the oldest supported OS; do not set the minimum to OS 26.

Local mapping: [DEPLOYMENT_TARGET_DECISION.md](DEPLOYMENT_TARGET_DECISION.md)

## G1 — External Production Gate: Subscription and Schema Proof

Classification: Release blocker until evidenced; not a source-code defect

Before submission, prove on physical devices that the production entitlement
selects the intended container, the deployed schema has the encrypted fields,
the database subscription installs, a silent peer notification arrives, token
fetch converges, and deletion remains paused until explicit re-enable.

Primary sources:

- [CKContainer](https://developer.apple.com/documentation/cloudkit/ckcontainer)
- [Deploying an iCloud container's schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)
- [CKDatabaseSubscription](https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription)

## Confirmed Strengths

- All CloudKit wire fields use CloudKit encrypted fields and sync does not query
  them. Full end-to-end key exclusivity additionally depends on Advanced Data
  Protection.
- Request batching has both proactive count/byte bounds and recursive
  `limitExceeded` subdivision.
- CKRecord system fields are cached for change-tag conflict safety.
- Notifications are treated as hints and changes are fetched with tokens.
- Users have native view/export and CloudKit deletion controls, with the
  completeness caveat in F9.
- The two first-party privacy manifests agree and the `C617.1` file-metadata
  reason matches the first-party `stat(2)` use on app-managed database
  identity; no arbitrary user-file timestamp access was found.

## 2025–2026 Opportunity Ordering

The newer APIs are opportunities, not reasons to raise the minimum to OS 26 or
to expand the frozen schema prematurely:

1. Foundation Models can provide optional, on-device structured proposals or
   summaries after availability checks and user confirmation. See
   [FOUNDATION_MODELS_2025_2026.md](FOUNDATION_MODELS_2025_2026.md).
2. `BGContinuedProcessingTask` can support user-started long exports/imports,
   but cannot replace the silent-push deadline. See
   [BACKGROUND_CONTINUED_PROCESSING_2025.md](BACKGROUND_CONTINUED_PROCESSING_2025.md).
3. AlarmKit is appropriate only for an explicitly chosen focus timer or
   must-alert workflow, not ordinary task reminders. See
   [ALARMKIT_2025.md](ALARMKIT_2025.md).
4. App schema, `IndexedEntity`, interactive snippets, and later
   `SyncableEntity` adoption should follow F17/F19/F22, so discoverability does
   not amplify authorization or index-protection defects.
