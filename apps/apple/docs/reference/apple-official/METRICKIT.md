# MetricKit

Source: [MetricKit](https://developer.apple.com/documentation/metrickit)

Last verified: 2026-07-10

## Apple Contract

MetricKit supplies system-captured, per-device performance and diagnostic
reports. Reports are delivered to the app, and an app chooses whether and where
to persist or upload them.

Apple's June 2026 documentation introduces `MetricManager` for iOS 27/macOS 27
and marks the older `MXMetricManager` subscriber API deprecated. The new API
delivers `MetricReport` and `DiagnosticReport` through asynchronous sequences.

## Lorvex Mapping

Lorvex uses `MXMetricManagerSubscriber` and stores selected crash/hang/CPU/disk
diagnostics in the local `error_logs` ring. This remains necessary for the iOS
17/macOS 14 deployment floor; the new API cannot simply replace it everywhere.

The privacy posture remains local because Lorvex does not add an upload path.
Product copy should describe what Lorvex itself does and avoid making guarantees
about operating-system diagnostics settings outside the app's control.

Apple's separate App Store/TestFlight crash-report pipeline is documented in
[APP_CRASH_REPORTS.md](APP_CRASH_REPORTS.md). In particular, a local-only
MetricKit implementation does not mean the operating system can never share a
crash report under Apple's own settings and distribution contracts.

## Maintenance Finding

This is not a blocker for the current Xcode 26 submission toolchain, but it is no
longer merely an indefinite low-severity cleanup: the deprecated subscriber is
Lorvex's only MetricKit receiver. Treat the migration as an Xcode 27 adoption
gate. An availability-gated adapter should use `MetricManager` on OS 27+ while
retaining the MX path for older systems; Xcode 27 beta should be used as a
warning/build/concurrency probe before it becomes the required submission
toolchain.

The subscriber also discards every aggregate metric payload, so the local store
cannot establish launch, resume, responsiveness, memory, exit, CPU, disk, or
energy regressions. The full source and release-evidence assessment is in
[APPLE_SIGNED_RELEASE_PERFORMANCE_METRICKIT_AUDIT.md](APPLE_SIGNED_RELEASE_PERFORMANCE_METRICKIT_AUDIT.md).
