#if canImport(MetricKit)
  import Foundation
  import MetricKit
  import os

  /// Registers on `MXMetricManager` and persists MetricKit diagnostics *and*
  /// aggregate metric summaries into the local `error_logs` ring via
  /// ``LorvexCoreServicing/appendDiagnosticLog(source:level:message:details:)``.
  ///
  /// Diagnostics: one `error_logs` row per crash / hang / CPU-exception /
  /// disk-write diagnostic, mapped by ``MetricKitDiagnosticMapper``
  /// (`source`/`level`/`message`) with the diagnostic's own
  /// `jsonRepresentation()` as `details`.
  ///
  /// Metric payloads: each daily `MXMetricPayload` is reduced to a bounded
  /// ``MetricKitMetricsSummary`` (launch/resume/hang, peak/suspended memory,
  /// CPU, logical disk writes, and foreground/background exit counts) and
  /// persisted as one `info`-level `metrickit.metrics` row with a compact JSON
  /// `details`, so a new release's launch, memory, exit, CPU, or disk
  /// regressions are readable from the local diagnostics feed. A payload with
  /// no extractable metrics is skipped rather than logged as an empty
  /// breadcrumb. These summaries are local observability only — never written to
  /// CloudKit or the synced data schema; ``MetricKitDiagnosticMapper/kind(forSource:)``
  /// classifies `metrickit.metrics` as non-diagnostic so the crash-scoped feed
  /// never surfaces them.
  ///
  /// Available on iOS 14+ / macOS 12+ / visionOS 1+ — the platforms MetricKit
  /// vends `MXDiagnosticPayload` on; `#if canImport(MetricKit)` excludes watchOS,
  /// which has no MetricKit. The app's iOS 18 / macOS 15 floor clears the
  /// diagnostics API's version requirement, so no runtime `@available` gate is
  /// needed.
  public final class MetricKitDiagnosticsSubscriber: NSObject, MXMetricManagerSubscriber {
    private static let log = Logger(subsystem: "com.lorvex.apple", category: "metrickit")

    private let resolveService: @Sendable () -> any LorvexCoreServicing

    /// Retains the process-wide subscriber. `MXMetricManager.add(_:)` does not
    /// keep a strong reference, so without this the subscriber would deallocate
    /// and stop receiving payloads. `nonisolated(unsafe)` with a lock: written
    /// once at launch, read only by ``register(resolveService:)``.
    private nonisolated(unsafe) static var shared: MetricKitDiagnosticsSubscriber?
    private static let sharedLock = NSLock()

    public init(resolveService: @escaping @Sendable () -> any LorvexCoreServicing) {
      self.resolveService = resolveService
      super.init()
    }

    /// Installs one subscriber on `MXMetricManager.shared`, retaining it for the
    /// app's lifetime. Idempotent: a second call returns the existing instance
    /// without registering again. `resolveService` defaults to the notification
    /// surface's cached core service, the same non-app writer seam widgets and
    /// notification actions use, so diagnostics land in the app's database
    /// without minting an HLC (an `error_logs` insert is not a sync mutation).
    @discardableResult
    public static func register(
      resolveService: @escaping @Sendable () -> any LorvexCoreServicing = {
        LorvexCoreRuntimeFactory.makeForNotification()
      }
    ) -> MetricKitDiagnosticsSubscriber {
      sharedLock.lock()
      defer { sharedLock.unlock() }
      if let existing = shared { return existing }
      let subscriber = MetricKitDiagnosticsSubscriber(resolveService: resolveService)
      shared = subscriber
      MXMetricManager.shared.add(subscriber)
      return subscriber
    }

    // MARK: - MXMetricManagerSubscriber

    /// Persist one compact `metrickit.metrics` `error_logs` row per aggregate
    /// metric payload, skipping any payload that yields no measured metrics.
    public func didReceive(_ payloads: [MXMetricPayload]) {
      for payload in payloads {
        let summary = Self.summary(from: payload)
        guard summary.hasMetrics else { continue }
        persist(MetricKitDiagnosticMapper.record(for: summary))
      }
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
      for record in payloads.flatMap(Self.records(from:)) {
        persist(record)
      }
    }

    /// Flatten one diagnostic payload into per-diagnostic `error_logs` records,
    /// in crash → hang → CPU → disk order.
    static func records(from payload: MXDiagnosticPayload) -> [MetricKitLogRecord] {
      var records: [MetricKitLogRecord] = []
      for crash in payload.crashDiagnostics ?? [] {
        records.append(MetricKitDiagnosticMapper.record(for: fields(from: crash)))
      }
      for hang in payload.hangDiagnostics ?? [] {
        records.append(MetricKitDiagnosticMapper.record(for: fields(from: hang)))
      }
      for cpu in payload.cpuExceptionDiagnostics ?? [] {
        records.append(MetricKitDiagnosticMapper.record(for: fields(from: cpu)))
      }
      for disk in payload.diskWriteExceptionDiagnostics ?? [] {
        records.append(MetricKitDiagnosticMapper.record(for: fields(from: disk)))
      }
      return records
    }

    /// Persist one diagnostic row in a detached task (the `MXMetricManagerSubscriber`
    /// callback is synchronous, so the write must bridge to async). A failure is
    /// logged rather than swallowed, so a persistence bug is visible in the log
    /// instead of silently dropping the diagnostic.
    private func persist(_ record: MetricKitLogRecord) {
      let service = resolveService()
      let log = Self.log
      Task.detached {
        do {
          try await service.appendDiagnosticLog(
            source: record.source, level: record.level,
            message: record.message, details: record.details)
        } catch {
          log.error(
            """
            MetricKit diagnostic persist failed for \(record.source, privacy: .public): \
            \(String(describing: error), privacy: .public)
            """)
        }
      }
    }

    // MARK: - Field extraction

    private static func json(_ diagnostic: MXDiagnostic) -> String? {
      String(data: diagnostic.jsonRepresentation(), encoding: .utf8)
    }

    private static func fields(from crash: MXCrashDiagnostic) -> MetricKitDiagnosticFields {
      MetricKitDiagnosticFields(
        kind: .crash,
        exceptionType: crash.exceptionType?.intValue,
        exceptionCode: crash.exceptionCode?.intValue,
        signal: crash.signal?.intValue,
        terminationReason: crash.terminationReason,
        details: json(crash))
    }

    private static func fields(from hang: MXHangDiagnostic) -> MetricKitDiagnosticFields {
      MetricKitDiagnosticFields(
        kind: .hang,
        hangDurationSeconds: hang.hangDuration.converted(to: .seconds).value,
        details: json(hang))
    }

    private static func fields(from cpu: MXCPUExceptionDiagnostic) -> MetricKitDiagnosticFields {
      MetricKitDiagnosticFields(
        kind: .cpuException,
        cpuTimeSeconds: cpu.totalCPUTime.converted(to: .seconds).value,
        details: json(cpu))
    }

    private static func fields(from disk: MXDiskWriteExceptionDiagnostic)
      -> MetricKitDiagnosticFields
    {
      MetricKitDiagnosticFields(
        kind: .diskWriteException,
        diskWritesBytes: disk.totalWritesCaused.converted(to: .bytes).value,
        details: json(disk))
    }

    // MARK: - Metric-payload extraction

    /// Reduce one aggregate `MXMetricPayload` to a bounded
    /// ``MetricKitMetricsSummary``. Every field is optional: MetricKit omits
    /// whole metric groups per payload, so an absent group stays nil rather than
    /// a fabricated zero. Durations become the histograms' count-weighted means.
    static func summary(from payload: MXMetricPayload) -> MetricKitMetricsSummary {
      let iso8601 = ISO8601DateFormatter()

      var foregroundExits: Int?
      var backgroundExits: Int?
      var memoryLimitExits: Int?
      var watchdogExits: Int?
      var taskTimeoutExits: Int?
      var lockedFileExits: Int?
      if let exitMetrics = payload.applicationExitMetrics {
        let fg = exitMetrics.foregroundExitData
        let bg = exitMetrics.backgroundExitData
        foregroundExits =
          fg.cumulativeNormalAppExitCount + fg.cumulativeMemoryResourceLimitExitCount
          + fg.cumulativeBadAccessExitCount + fg.cumulativeAbnormalExitCount
          + fg.cumulativeIllegalInstructionExitCount + fg.cumulativeAppWatchdogExitCount
        backgroundExits =
          bg.cumulativeNormalAppExitCount + bg.cumulativeMemoryResourceLimitExitCount
          + bg.cumulativeCPUResourceLimitExitCount + bg.cumulativeMemoryPressureExitCount
          + bg.cumulativeBadAccessExitCount + bg.cumulativeAbnormalExitCount
          + bg.cumulativeIllegalInstructionExitCount + bg.cumulativeAppWatchdogExitCount
          + bg.cumulativeSuspendedWithLockedFileExitCount
          + bg.cumulativeBackgroundTaskAssertionTimeoutExitCount
        memoryLimitExits =
          fg.cumulativeMemoryResourceLimitExitCount + bg.cumulativeMemoryResourceLimitExitCount
        watchdogExits = fg.cumulativeAppWatchdogExitCount + bg.cumulativeAppWatchdogExitCount
        taskTimeoutExits = bg.cumulativeBackgroundTaskAssertionTimeoutExitCount
        lockedFileExits = bg.cumulativeSuspendedWithLockedFileExitCount
      }

      return MetricKitMetricsSummary(
        intervalStart: iso8601.string(from: payload.timeStampBegin),
        intervalEnd: iso8601.string(from: payload.timeStampEnd),
        appVersion: payload.latestApplicationVersion,
        osVersion: payload.metaData?.osVersion,
        launchTimeMs: payload.applicationLaunchMetrics.flatMap {
          meanMilliseconds($0.histogrammedTimeToFirstDraw)
        },
        resumeTimeMs: payload.applicationLaunchMetrics.flatMap {
          meanMilliseconds($0.histogrammedApplicationResumeTime)
        },
        hangTimeMs: payload.applicationResponsivenessMetrics.flatMap {
          meanMilliseconds($0.histogrammedApplicationHangTime)
        },
        peakMemoryMB: payload.memoryMetrics.map {
          rounded($0.peakMemoryUsage.converted(to: .megabytes).value, places: 1)
        },
        suspendedMemoryMB: payload.memoryMetrics.map {
          rounded(
            $0.averageSuspendedMemory.averageMeasurement.converted(to: .megabytes).value, places: 1)
        },
        cpuTimeSeconds: payload.cpuMetrics.map {
          rounded($0.cumulativeCPUTime.converted(to: .seconds).value, places: 1)
        },
        logicalWriteKB: payload.diskIOMetrics.map {
          rounded($0.cumulativeLogicalWrites.converted(to: .kilobytes).value, places: 1)
        },
        foregroundExitCount: foregroundExits,
        backgroundExitCount: backgroundExits,
        memoryResourceLimitExitCount: memoryLimitExits,
        appWatchdogExitCount: watchdogExits,
        backgroundTaskAssertionTimeoutExitCount: taskTimeoutExits,
        suspendedWithLockedFileExitCount: lockedFileExits)
    }

    /// Count-weighted mean of a duration histogram's bucket midpoints, in
    /// milliseconds (rounded to whole ms), or nil for an empty histogram — no
    /// samples in the window means "unmeasured", not zero.
    private static func meanMilliseconds(_ histogram: MXHistogram<UnitDuration>) -> Double? {
      var totalCount = 0
      var weightedSum = 0.0
      for case let bucket as MXHistogramBucket<UnitDuration> in histogram.bucketEnumerator {
        let midpoint =
          (bucket.bucketStart.converted(to: .milliseconds).value
            + bucket.bucketEnd.converted(to: .milliseconds).value) / 2
        weightedSum += midpoint * Double(bucket.bucketCount)
        totalCount += bucket.bucketCount
      }
      guard totalCount > 0 else { return nil }
      return rounded(weightedSum / Double(totalCount), places: 0)
    }

    private static func rounded(_ value: Double, places: Int) -> Double {
      let factor = pow(10.0, Double(places))
      return (value * factor).rounded() / factor
    }
  }
#endif
