# Apple API Deprecation Audit

This is a Lorvex source audit against Xcode 26.6 / macOS 26.5 SDK declarations
and current Apple documentation. It contains no implementation changes.

Last verified: 2026-07-10

## Confirmed Shipping Hits

| API | Lorvex count | Apple direction | Priority |
| --- | ---: | --- | --- |
| `AppIntent.openAppWhenRun` | 99 intent types | Use `supportedModes` on OS 26 | Before release, centralized migration |
| `NSApplication.activate(ignoringOtherApps:)` | 6 call sites | Use `activate()`; replacement exists since macOS 14 | Before release |
| `EKAuthorizationStatus.authorized` beside `.fullAccess` | 7 switch cases | Use full/write-only states since macOS 14/iOS 17 | Before release |
| SwiftUI `Text + Text` | 3 operations in one renderer | Use interpolation | Before release |
| `MXMetricManager` / subscriber protocol | One process-wide service | Use OS 27 `MetricManager` async sequences | Xcode 27 adapter |

The `NSApplication` SDK header describes the old activation method as planned
for deprecation and directs callers to `activate()`. It has no compatibility
benefit because Lorvex's existing minimum is macOS 14.

The EventKit legacy `authorized` case aliases `fullAccess` and was deprecated in
the exact macOS 14 / iOS 17 generation Lorvex already requires. Keeping both
obscures whether write-only access is handled deliberately.

Because the complete App Intent surface depends on the deprecated Boolean,
`openAppWhenRun` is more than a cosmetic warning. Migrate it together with the
authentication/confirmation classification so each intent receives one
explicit execution policy. A blind 99-file replacement could change background
and foreground behavior.

## Why the Ordinary Build Can Miss This

A SwiftPM build of the macOS-14 package with Xcode 26.6 completed without
deprecation warnings. Availability-aware diagnostics are incomplete when a
legacy declaration remains necessary for an older deployment target, and some
imported aliases do not warn consistently.

The release gate therefore needs both:

- a warnings-as-errors build at the supported minimum; and
- a source/SDK deprecation probe against the current and next SDK generation.

Do not suppress a framework-wide warning group. Put legacy declarations in a
small adapter and test both runtime branches.

## Negative Results

The source uses modern two-parameter SwiftUI `onChange`; no `NavigationView`,
single-parameter `onChange`, legacy EventKit `requestAccess(to:)`, status-bar
accessors, or old MobileCoreServices type constants were found in shipping
sources. WatchConnectivity remains the documented companion-app transport.

## Related Primary Sources

- [AppIntent.openAppWhenRun](https://developer.apple.com/documentation/appintents/appintent/openappwhenrun)
- [AppIntent.supportedModes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)
- [MetricKit updates](https://developer.apple.com/documentation/updates/metrickit)
- [macOS 26 Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes)
