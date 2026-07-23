# Apple Multi-OS Versioning and App Store Routing

Last verified: 2026-07-10

This note explains how an app adopts OS 27 APIs while remaining installable on
iOS 18 or macOS 15. It also separates runtime availability, App Store version
eligibility, last-compatible downloads, architecture routing, and app thinning.

## Primary Apple Sources

- [Running code on a specific platform or OS version](https://developer.apple.com/documentation/xcode/running-code-on-a-specific-version)
- [Marking and checking API availability](https://developer.apple.com/documentation/swift/marking-api-availability-in-objective-c)
- [`MinimumOSVersion`](https://developer.apple.com/documentation/bundleresources/information-property-list/minimumosversion)
- [View build requirements in App Store Connect](https://developer.apple.com/help/app-store-connect/manage-builds/view-builds-and-metadata/)
- [Last-Compatible Version Settings](https://developer.apple.com/help/app-store-connect/reference/pricing-and-availability/app-pricing-and-availability)
- [Make a version unavailable for download](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/make-a-version-unavailable-for-download)
- [App thinning and device variants](https://developer.apple.com/documentation/xcode/doing-advanced-optimization-to-further-reduce-your-app-s-size)
- [Testing a Release build](https://developer.apple.com/documentation/xcode/testing-a-release-build)

## Short Answer

Most apps do **not** choose between these two extremes:

- forever avoid every API newer than their oldest supported OS; or
- upload a separately maintained current app for each OS version and ask the App
  Store to select the implementation.

The normal design is one current app binary, built with a recent SDK, whose
deployment target remains one or two OS generations older. Newer systems execute
availability-gated code; older systems execute a fallback in the same binary.
Apple explicitly recommends this approach instead of creating a separate
project for each OS release.

The App Store decides whether the binary is eligible for a device. It does not
choose the app's `if #available` branch. The operating system does that at
runtime.

## The Independent Axes

| Axis | What it controls | Lorvex example |
| --- | --- | --- |
| SDK/Xcode | APIs the source can compile against | build an experimental lane with Xcode 27 |
| deployment target | oldest OS allowed to install/launch this binary | iOS 18, macOS 15 |
| architecture | CPU slice the executable can run | arm64-only Mac |
| required capabilities | hardware/features required for installation | declare only true app-wide requirements |
| runtime availability | which feature branch runs now | OS 27 App Schema versus existing App Intent |
| runtime readiness | device/setting/language/network/model state | Foundation Model available versus deterministic capture |
| App thinning | which slices/assets the App Store delivers | device-specific executable/resources |
| last-compatible version | an older submitted build an existing customer may redownload | emergency compatibility, not active dual development |

An arm64 Mac running macOS 15 can install an arm64 app with a macOS 15 target
even when that app was compiled with the macOS 27 SDK. The same Mac cannot
install a binary whose minimum system version is macOS 27. Architecture and OS
minimum are separate decisions.

## How One Binary Uses New APIs

### Runtime checks

Use `if #available` when the current execution needs a new API:

```swift
if #available(iOS 27, macOS 27, *) {
  // OS 27 implementation.
} else {
  // Complete iOS 18 / macOS 15 fallback.
}
```

Use `@available` to isolate a declaration whose implementation is entirely
new-platform code:

```swift
@available(iOS 27, macOS 27, *)
struct SiriSchemaIntegration {
  // OS 27-only types remain inside this boundary.
}
```

The compiler checks that callers cross the boundary safely. System frameworks
and symbols are weak-linked as required; the old OS never calls the unavailable
symbol when the availability boundary is correct.

### Compile-time checks are different

`#if os(iOS)`, `#if canImport(...)`, and build settings decide which code is
compiled into a target. They are useful for platform differences or an SDK that
lacks an entire module. They do not ask which OS version the customer's device
is currently running.

Scattering compile-time flags through business logic easily creates multiple
untestable products. Prefer a small adapter or capability boundary, then keep
domain behavior shared.

### New Swift syntax is not the same as a new OS API

Many language features are implemented by the compiler and can be used while
targeting an older OS. Other features depend on a newer standard-library or
runtime capability and may be back-deployed by the toolchain or carry their own
availability requirement. The compiler establishes that boundary.

By contrast, a type supplied by an OS 27 framework is not made available on iOS
18 merely because the source uses new Swift syntax. Keep the questions separate:
“Can this source compile with this Swift toolchain?” and “Does this symbol exist
on the customer's OS?”

### Runtime capability is more than the OS number

Foundation Models demonstrates why `if #available` is necessary but
insufficient. On OS 26/27 the model can still be unavailable because the device
is ineligible, Apple Intelligence is off, the language or region is unsupported,
the model is downloading, the network is absent, or a PCC quota is exhausted.

The product should ask a capability service whether “intelligent capture” is
usable and what fallback to show. Views should not equate “OS 27” with “AI
works.”

## What the App Store Routes

### Latest eligible build

App Store Connect derives the minimum OS, architectures, device families, and
required capabilities from the submitted build. A device receives the latest
available build it is eligible to run. If the current build requires iOS 27, an
iOS 18 device cannot install that build.

### App thinning

The App Store can deliver a variant containing only the code slices and assets
needed by a particular device. This reduces download/install size. App thinning
does not maintain two behavioral implementations and does not turn a new API
into an old-OS-compatible API.

### Last-compatible version

App Store Connect retains submitted versions that can be made available for
existing customers to download again from iCloud. The developer can exclude a
version with legal or usability problems through Last-Compatible Version
Settings.

This is not equivalent to an actively maintained old-OS release channel:

- the older build receives no new fixes unless another compatible build is
  submitted before the floor is raised;
- an old build may continue syncing with a newer build, so data protocol
  compatibility still matters;
- Apple's documentation frames this as availability for existing customers;
- a bad historical build must be explicitly removed from last-compatible
  downloads;
- product behavior, support copy, and server compatibility can drift.

Do not raise the floor assuming App Store history will solve support and
security maintenance automatically.

### Separate apps/builds

Separate bundle IDs or products are possible, and one App Store record can have
platform-specific iPhone/iPad/Mac builds. That is appropriate when the products
are genuinely different. It is normally unnecessary and expensive for two iOS
implementations that differ only by API availability.

## What Large Apps Commonly Do

1. Build with a current required SDK while keeping a deliberate older deployment
   target.
2. Put new framework usage behind `@available` adapters.
3. Provide an old-OS implementation or omit only the optional enhancement.
4. Use server-side feature flags for staged product rollout, not to bypass OS
   symbol availability.
5. Keep a shared domain/data layer and vary presentation/system integrations.
6. Test the oldest supported OS, current stable OS, and next beta separately.
7. Raise the floor periodically when the user share and test/support cost
   justify it.

They still use new features. They simply avoid making every new feature an
unconditional reference from code that runs on the minimum OS.

## Recommended Lorvex Shape

Lorvex now declares macOS 15 and iOS 18 in both Swift packages, XcodeGen, and
the relevant Info plists. Keep one product with layers like:

| Layer | Minimum-OS behavior | New-OS enhancement |
| --- | --- | --- |
| core/domain/SQLite/CloudKit | identical canonical behavior | identical canonical behavior |
| App Intents | existing typed intents and Shortcuts | OS 27 App Schemas, view annotations, system tests |
| capture | manual text/fields | on-device structured extraction, OS 27 image/OCR |
| search | deterministic database search | protected Spotlight semantic search/local RAG |
| planning | deterministic metrics and editable scheduler | AI-generated proposal, never silent commit |
| UI | complete iOS 18/macOS 15 experience | optional newer presentation/system surfaces |

Centralize each family:

- `IntelligenceCapabilityResolver`
- `SiriIntegrationAdapter`
- `PlannerSearchProvider`
- `ReleaseFeaturePolicy`

The names are illustrative; the architectural point is to avoid placing
`if #available` in every view and each of the many App Intent declarations.

## Data Compatibility Is the Hard Part

Different UI/API branches are relatively easy. Cross-version persistent data is
where accidental debt appears:

- An AI-assisted iOS 27 capture should commit an ordinary task that iOS 18 can
  already read.
- Do not add strict synced enum cases that the older binary rejects.
- Unknown optional fields need an explicitly tested forward-compatibility
  policy before they enter a sync payload.
- Model transcripts, embeddings, provider objects, and hidden reasoning should
  remain local/ephemeral instead of becoming CloudKit schema.
- Entity identifiers used by Siri, Spotlight, widgets, deep links, SQLite, and
  CloudKit should remain the same stable identity.
- If an older last-compatible build can still connect to the same CloudKit
  container, every new writer must remain safe for that reader.

This is why OS 27 intelligence can be adopted aggressively at the integration
layer while the canonical data schema remains conservative.

## Release Matrix

For every feature family, test:

| Environment | Expected result |
| --- | --- |
| iOS 18 / macOS 15 | no unavailable-symbol crash; complete deterministic path |
| OS 26 eligible device | OS 26 Foundation Models features only, with runtime availability checks |
| OS 26 ineligible/disabled/not-ready | honest non-AI fallback |
| OS 27 eligible device | new App Schema/image/PCC paths as enabled |
| OS 27 beta versus final | no assumption that beta behavior/API is frozen |
| offline / PCC quota exhausted | on-device or deterministic fallback |
| upgrade from old build | data and settings remain readable |
| old last-compatible build beside newer synced device | no unknown-enum/schema failure or destructive divergence |

The practical recommendation is therefore straightforward: keep iOS 18 and
macOS 15, compile and test OS 27 integrations in a contained lane, and ship new
features opportunistically from one binary once the SDK and behavior stabilize.
The App Store will route compatible binaries and device variants; Lorvex itself
must route feature behavior safely.
