# Apple Platform Deployment-Target Decision

This is a Lorvex source-audit decision note rather than a copy of an Apple
page. It separates the SDK used to build the app from the oldest OS allowed to
install it.

Last verified: 2026-07-10

## Recommended Release Baseline

- Build and submit with the current Xcode 26 toolchain and version 26 SDKs.
- Set the intended minimum generation to macOS 15, iOS/iPadOS 18, watchOS 11,
  and visionOS 2.
- Treat arm64 as the primary/default Mac artifact. A universal artifact may
  remain an optional secondary deliverable, but it should not force product or
  test compatibility decisions for Intel hardware.
- Keep OS 26 features behind a small, centralized availability layer until the
  version-15/18 generation is retired.

The repository now declares macOS 15, iOS 18, watchOS 11, and visionOS 2 in its
Swift packages, XcodeGen deployment settings, and relevant static Info plists.

## SDK Versus Minimum OS

Building with Xcode 26 and the macOS 26 SDK does not exclude macOS 15. A binary
whose deployment target is macOS 15 can run there, provided every OS 26 API is
availability-gated or has a fallback.

Changing `MACOSX_DEPLOYMENT_TARGET`, `LSMinimumSystemVersion`, or SwiftPM's
platform declaration to macOS 26 is different: macOS 15 refuses to install or
launch that binary, including on an M1/M2/M3/M4/M5 Mac.

Architecture is another independent axis. An arm64-only binary can support
macOS 15, while a universal binary with a macOS 26 deployment target still
cannot run on macOS 15.

## Why Not macOS 11

Big Sur was the first OS shipped on Apple silicon, but it is not a useful API
floor for Lorvex. The current code already assumes the macOS 14 generation,
including the modern EventKit authorization model, Observation, two-argument
SwiftUI `onChange`, and other APIs. Lowering the floor would add compatibility
branches without adding Apple-silicon hardware coverage.

## Why macOS 15 / iOS 18 Is the Balanced Floor

- It preserves users who have not moved to the version-26 OS generation.
- It makes `Synchronization.Mutex` available across the platform family,
  enabling scoped state protection instead of many manual `NSLock` regions.
- It is the natural generation for newer App Intents/Core Spotlight entity
  integration such as `IndexedEntity`.
- It keeps only one older runtime generation beneath the current stable 26
  generation, rather than retaining the 2023 macOS 14/iOS 17 baseline.

Apple publishes current iPhone/iPad adoption but no equivalent public macOS
percentage. The iPhone figure is evidence against assuming every current user
has upgraded to 26; it is not a substitute for Lorvex's own post-launch data.

## OS 26 Compatibility Layer That Remains

With a macOS 15 / iOS 18 floor, Lorvex still needs dual behavior for:

- `AppIntent.supportedModes` on OS 26 and the legacy execution declaration on
  older systems;
- Liquid Glass and OS 26-only SwiftUI presentation APIs;
- typed NotificationCenter messages and Observation async sequences if
  adopted;
- any Foundation Models feature, with additional runtime checks for model
  availability, language, region, and device state.

The dual behavior should live in shared policy/adapters, not in 99 independent
App Intent declarations.

The concrete one-binary/App-Store behavior is documented in
[APPLE_MULTI_OS_VERSIONING_AND_APP_STORE_ROUTING.md](APPLE_MULTI_OS_VERSIONING_AND_APP_STORE_ROUTING.md).

## Current Sources of Version Truth

The present floor is duplicated across both `Package.swift` files, XcodeGen's
`deploymentTarget`, static mobile/vision Info plists, the MCP helper Info plist,
and `script/app_metadata.sh`. A release change must explicitly prove parity
across all of these locations.

## Release Evidence

For each public release, retain build-and-test evidence for:

1. the oldest supported OS generation on physical or virtual hardware;
2. the current stable OS generation;
3. the current required App Store SDK/toolchain;
4. the arm64 Mac artifact's complete nested Mach-O closure;
5. any optional universal artifact as a separate, non-default matrix entry.

## Primary Sources

- [Apple App Store OS usage](https://developer.apple.com/support/app-store/)
- [macOS Tahoe 26 compatibility](https://support.apple.com/en-ie/122727)
- [Apple Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)
