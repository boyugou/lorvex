# Swift 6.2 Modernization

Primary sources:

- [Swift 6.2 Released](https://www.swift.org/blog/swift-6.2-released/)
- [What's new in Swift — WWDC25](https://developer.apple.com/videos/play/wwdc2025/245/)
- [Embracing Swift concurrency — WWDC25](https://developer.apple.com/videos/play/wwdc2025/268/)

Last verified: 2026-07-10

## Apple and Swift Project Direction

Swift 6.2 added approachable-concurrency settings, caller-context execution for
ordinary async functions, explicit `@concurrent` work, improved diagnostics,
typed NotificationCenter messages, Observation async sequences, and newer
testing capabilities.

Apple recommends enabling Approachable Concurrency generally and using
main-actor default isolation for UI-focused modules. These are compiler/module
decisions; most do not require raising the deployment target to OS 26.

## Lorvex Mapping

Strengths:

- The packages already use Swift 6 language mode.
- The six mutable UI stores/models use Observation's `@Observable`; there are
  no shipping `ObservableObject`, `@Published`, `@StateObject`, or
  `@EnvironmentObject` remnants.

Modernization gaps:

- No target enables Approachable Concurrency or deliberate default isolation.
- Thirteen source files instantiate `NSLock`; none uses
  `Synchronization.Mutex`. `Mutex` is available at exactly the proposed
  macOS 15 / iOS 18 / watchOS 11 / visionOS 2 floor and couples protected state
  with scoped access.
- The source contains many `@unchecked Sendable`, `nonisolated(unsafe)`, and
  `@preconcurrency` escape hatches. Some are justified wrappers around imported
  frameworks or locks, but they should be re-proven under the current SDK.
- Lorvex has nine notification posts and nine observer/async-stream sites using
  string names and untyped payloads. Typed NotificationCenter messages are OS
  26-only, so they are a future adapter opportunity, not a reason to raise the
  first-release minimum.

## Adoption Direction

1. Enable Swift 6.2 migration diagnostics first and capture behavior-preserving
   fix-its.
2. Apply main-actor default isolation only to UI/executable targets; do not put
   storage, sync, MCP, or CloudKit engines on the main actor by default.
3. Mark deliberately parallel CPU work `@concurrent` only after profiling.
4. Migrate lock-protected state to `Mutex` one invariant at a time, retaining
   stress/race tests for each conversion.
5. Audit every unsafe sendability escape; do not perform a mechanical removal.
6. Keep Xcode 27 / Swift 6.4 features as a compatibility probe until that
   toolchain is stable and accepted for submission.

These changes can simplify concurrency contracts but do not require or justify
a data-schema migration.

