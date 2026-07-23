import Foundation

/// One row destined for the `error_logs` diagnostics ring, mapped from a single
/// MetricKit diagnostic. The four fields are exactly the `error_logs` columns a
/// diagnostic populates: `source` classifies the diagnostic kind
/// (`metrickit.crash` / `.hang` / `.cpu_exception` / `.disk_write`), `level` is
/// `error` for crashes and hangs and `warn` for the resource exceptions,
/// `message` is a one-line human summary, and `details` carries the raw
/// per-diagnostic `jsonRepresentation()` payload (or `nil`).
public struct MetricKitLogRecord: Sendable, Equatable {
  public let source: String
  public let level: String
  public let message: String
  public let details: String?

  public init(source: String, level: String, message: String, details: String?) {
    self.source = source
    self.level = level
    self.message = message
    self.details = details
  }
}

/// Platform-neutral projection of a MetricKit diagnostic: the handful of fields
/// ``MetricKitDiagnosticMapper`` needs to classify a diagnostic and compose its
/// summary, decoupled from the `MetricKit` `MX*Diagnostic` types so the mapping
/// is unit-testable without fabricating framework objects (the `MX*Diagnostic`
/// classes expose no usable initializer).
public struct MetricKitDiagnosticFields: Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    case crash
    case hang
    case cpuException
    case diskWriteException
  }

  public var kind: Kind
  /// Crash: Mach exception type, exception code, and POSIX signal — any of
  /// which MetricKit may omit.
  public var exceptionType: Int?
  public var exceptionCode: Int?
  public var signal: Int?
  /// Crash: the OS-provided termination reason string, when present.
  public var terminationReason: String?
  /// Hang: unresponsive duration, in seconds.
  public var hangDurationSeconds: Double?
  /// CPU exception: attributed CPU time, in seconds.
  public var cpuTimeSeconds: Double?
  /// Disk-write exception: bytes of disk writes attributed to the app.
  public var diskWritesBytes: Double?
  /// The diagnostic's `jsonRepresentation()` decoded as UTF-8, stored verbatim
  /// in the `error_logs.details` column.
  public var details: String?

  public init(
    kind: Kind,
    exceptionType: Int? = nil,
    exceptionCode: Int? = nil,
    signal: Int? = nil,
    terminationReason: String? = nil,
    hangDurationSeconds: Double? = nil,
    cpuTimeSeconds: Double? = nil,
    diskWritesBytes: Double? = nil,
    details: String? = nil
  ) {
    self.kind = kind
    self.exceptionType = exceptionType
    self.exceptionCode = exceptionCode
    self.signal = signal
    self.terminationReason = terminationReason
    self.hangDurationSeconds = hangDurationSeconds
    self.cpuTimeSeconds = cpuTimeSeconds
    self.diskWritesBytes = diskWritesBytes
    self.details = details
  }
}

/// A bounded, privacy-safe projection of one `MXMetricPayload` — the aggregate
/// daily metrics with explicit release budgets — decoupled from the `MetricKit`
/// `MX*Metric` types so the summary is unit-testable without fabricating
/// framework objects (which expose no usable initializer).
///
/// Every field is optional: a payload omits whole metric groups, and MetricKit
/// is unavailable per platform. ``MetricKitDiagnosticMapper/record(for:)-``
/// serializes the present fields into a compact JSON `details` string persisted
/// under the `metrickit.metrics` `error_logs` source, so a new release's launch,
/// hang, memory, CPU, disk, and exit regressions can be read from the local
/// diagnostics feed. The values are locally retained observability only — never
/// written to CloudKit or the synced data schema.
///
/// Durations are milliseconds, memory megabytes, CPU seconds, disk writes
/// kilobytes; exit fields are counts over the payload's window.
public struct MetricKitMetricsSummary: Sendable, Equatable, Codable {
  /// The payload's aggregation window (ISO-8601), so a regression can be pinned
  /// to a day and build.
  public var intervalStart: String?
  public var intervalEnd: String?
  /// The app build and OS the window's metrics were produced under — the axis a
  /// regression is compared across. Neither is user-authored content.
  public var appVersion: String?
  public var osVersion: String?
  /// Launch time to first draw / resume time, milliseconds (histogram
  /// count-weighted means).
  public var launchTimeMs: Double?
  public var resumeTimeMs: Double?
  /// Mean app-hang (unresponsiveness) time, milliseconds.
  public var hangTimeMs: Double?
  /// Peak footprint / mean suspended footprint, megabytes.
  public var peakMemoryMB: Double?
  public var suspendedMemoryMB: Double?
  /// Cumulative CPU time, seconds.
  public var cpuTimeSeconds: Double?
  /// Cumulative logical disk writes, kilobytes.
  public var logicalWriteKB: Double?
  /// Foreground / background exit totals summed across all termination reasons.
  public var foregroundExitCount: Int?
  public var backgroundExitCount: Int?
  /// The release-relevant background termination reasons the audit calls out:
  /// memory-limit kills, watchdog kills, background-task timeouts, and
  /// suspend-with-locked-file (App-Group contention) kills.
  public var memoryResourceLimitExitCount: Int?
  public var appWatchdogExitCount: Int?
  public var backgroundTaskAssertionTimeoutExitCount: Int?
  public var suspendedWithLockedFileExitCount: Int?

  public init(
    intervalStart: String? = nil,
    intervalEnd: String? = nil,
    appVersion: String? = nil,
    osVersion: String? = nil,
    launchTimeMs: Double? = nil,
    resumeTimeMs: Double? = nil,
    hangTimeMs: Double? = nil,
    peakMemoryMB: Double? = nil,
    suspendedMemoryMB: Double? = nil,
    cpuTimeSeconds: Double? = nil,
    logicalWriteKB: Double? = nil,
    foregroundExitCount: Int? = nil,
    backgroundExitCount: Int? = nil,
    memoryResourceLimitExitCount: Int? = nil,
    appWatchdogExitCount: Int? = nil,
    backgroundTaskAssertionTimeoutExitCount: Int? = nil,
    suspendedWithLockedFileExitCount: Int? = nil
  ) {
    self.intervalStart = intervalStart
    self.intervalEnd = intervalEnd
    self.appVersion = appVersion
    self.osVersion = osVersion
    self.launchTimeMs = launchTimeMs
    self.resumeTimeMs = resumeTimeMs
    self.hangTimeMs = hangTimeMs
    self.peakMemoryMB = peakMemoryMB
    self.suspendedMemoryMB = suspendedMemoryMB
    self.cpuTimeSeconds = cpuTimeSeconds
    self.logicalWriteKB = logicalWriteKB
    self.foregroundExitCount = foregroundExitCount
    self.backgroundExitCount = backgroundExitCount
    self.memoryResourceLimitExitCount = memoryResourceLimitExitCount
    self.appWatchdogExitCount = appWatchdogExitCount
    self.backgroundTaskAssertionTimeoutExitCount = backgroundTaskAssertionTimeoutExitCount
    self.suspendedWithLockedFileExitCount = suspendedWithLockedFileExitCount
  }

  /// True when at least one measured metric (not just window/version metadata)
  /// is present. The subscriber skips persisting an all-metadata payload so a
  /// bare delivery never dilutes the diagnostics feed.
  public var hasMetrics: Bool {
    launchTimeMs != nil || resumeTimeMs != nil || hangTimeMs != nil || peakMemoryMB != nil
      || suspendedMemoryMB != nil || cpuTimeSeconds != nil || logicalWriteKB != nil
      || foregroundExitCount != nil || backgroundExitCount != nil
      || memoryResourceLimitExitCount != nil || appWatchdogExitCount != nil
      || backgroundTaskAssertionTimeoutExitCount != nil || suspendedWithLockedFileExitCount != nil
  }
}

/// Maps a MetricKit diagnostic onto the `error_logs` row it should become.
///
/// `source` and `level` are fixed per diagnostic kind; `message` is a compact,
/// locale-independent one-liner (crash exception/signal + termination reason,
/// hang/CPU/disk magnitude). Pure and deterministic so the mapping is testable
/// without the `MetricKit` framework.
public enum MetricKitDiagnosticMapper {
  public static func record(for fields: MetricKitDiagnosticFields) -> MetricKitLogRecord {
    MetricKitLogRecord(
      source: source(for: fields.kind),
      level: level(for: fields.kind),
      message: message(for: fields),
      details: fields.details)
  }

  /// The `error_logs.source` for an aggregate MetricKit metric summary. Distinct
  /// from the crash/hang diagnostic sources, so ``kind(forSource:)`` returns nil
  /// for it and a crash-scoped feed never surfaces a metrics breadcrumb.
  public static let metricsSource = "metrickit.metrics"

  /// Map an aggregate metric summary onto its `error_logs` row: the
  /// ``metricsSource`` source, `info` level (a regression signal, not a
  /// failure), a compact one-line human summary, and the present fields encoded
  /// as compact deterministic JSON in `details`.
  public static func record(for summary: MetricKitMetricsSummary) -> MetricKitLogRecord {
    MetricKitLogRecord(
      source: metricsSource,
      level: "info",
      message: metricsMessage(summary),
      details: metricsDetailsJSON(summary))
  }

  public static func source(for kind: MetricKitDiagnosticFields.Kind) -> String {
    switch kind {
    case .crash: return "metrickit.crash"
    case .hang: return "metrickit.hang"
    case .cpuException: return "metrickit.cpu_exception"
    case .diskWriteException: return "metrickit.disk_write"
    }
  }

  /// Reverse of ``source(for:)``: classify an `error_logs.source` value back to
  /// the MetricKit diagnostic kind that produced it, or `nil` for any other log
  /// source. Lets read surfaces scope a crash feed to — and label — the
  /// MetricKit rows without re-deriving the `metrickit.*` string constants.
  public static func kind(forSource source: String) -> MetricKitDiagnosticFields.Kind? {
    switch source {
    case "metrickit.crash": return .crash
    case "metrickit.hang": return .hang
    case "metrickit.cpu_exception": return .cpuException
    case "metrickit.disk_write": return .diskWriteException
    default: return nil
    }
  }

  /// Crashes and hangs are hard failures (`error`); CPU and disk-write
  /// exceptions are resource-pressure warnings (`warn`).
  public static func level(for kind: MetricKitDiagnosticFields.Kind) -> String {
    switch kind {
    case .crash, .hang: return "error"
    case .cpuException, .diskWriteException: return "warn"
    }
  }

  private static func message(for fields: MetricKitDiagnosticFields) -> String {
    switch fields.kind {
    case .crash:
      return crashMessage(fields)
    case .hang:
      guard let seconds = fields.hangDurationSeconds else { return "App hang" }
      return "App hang for \(secondsLabel(seconds))"
    case .cpuException:
      guard let seconds = fields.cpuTimeSeconds else { return "CPU exception" }
      return "CPU exception: \(secondsLabel(seconds)) of CPU time"
    case .diskWriteException:
      guard let bytes = fields.diskWritesBytes else { return "Excessive disk writes" }
      return "Excessive disk writes: \(bytesLabel(bytes))"
    }
  }

  private static func crashMessage(_ fields: MetricKitDiagnosticFields) -> String {
    var parts: [String] = []
    if let reason = fields.terminationReason?.trimmingCharacters(in: .whitespacesAndNewlines),
      !reason.isEmpty
    {
      parts.append(reason)
    }
    var codes: [String] = []
    if let type = fields.exceptionType { codes.append("exceptionType=\(type)") }
    if let code = fields.exceptionCode { codes.append("exceptionCode=\(code)") }
    if let signal = fields.signal { codes.append("signal=\(signal)") }
    if !codes.isEmpty { parts.append("(" + codes.joined(separator: ", ") + ")") }
    return parts.isEmpty ? "App crash" : "App crash: " + parts.joined(separator: " ")
  }

  /// `%.1f` uses the C locale, so the decimal separator is always `.` — the
  /// message stays stable under test regardless of the device locale.
  private static func secondsLabel(_ value: Double) -> String {
    String(format: "%.1fs", value)
  }

  private static func bytesLabel(_ bytes: Double) -> String {
    if bytes >= 1_000_000 { return String(format: "%.1f MB", bytes / 1_000_000) }
    if bytes >= 1_000 { return String(format: "%.1f KB", bytes / 1_000) }
    return String(format: "%.0f B", bytes)
  }

  /// A compact, locale-independent one-liner over the present metric fields, in a
  /// fixed order. `details` carries the full field set; this is the feed's
  /// glanceable summary.
  private static func metricsMessage(_ summary: MetricKitMetricsSummary) -> String {
    var parts: [String] = []
    if let value = summary.launchTimeMs { parts.append("launch \(msLabel(value))") }
    if let value = summary.resumeTimeMs { parts.append("resume \(msLabel(value))") }
    if let value = summary.hangTimeMs { parts.append("hang \(msLabel(value))") }
    if let value = summary.peakMemoryMB { parts.append("peakMem \(mbLabel(value))") }
    if let value = summary.cpuTimeSeconds { parts.append("cpu \(secondsLabel(value))") }
    if let value = summary.logicalWriteKB { parts.append("writes \(kbLabel(value))") }
    if let value = summary.foregroundExitCount { parts.append("fgExits \(value)") }
    if let value = summary.backgroundExitCount { parts.append("bgExits \(value)") }
    return parts.isEmpty
      ? "MetricKit metrics" : "MetricKit metrics: " + parts.joined(separator: ", ")
  }

  /// Encode the present summary fields as compact, key-sorted JSON for the
  /// `error_logs.details` column. Nil fields are omitted (synthesized
  /// `encodeIfPresent`), keeping the row small and truncation-resistant.
  private static func metricsDetailsJSON(_ summary: MetricKitMetricsSummary) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(summary),
      let json = String(data: data, encoding: .utf8)
    else { return nil }
    return json
  }

  private static func msLabel(_ value: Double) -> String { String(format: "%.0fms", value) }
  private static func mbLabel(_ value: Double) -> String { String(format: "%.1f MB", value) }
  private static func kbLabel(_ value: Double) -> String { String(format: "%.1f KB", value) }
}

extension RecentLogEntry {
  /// The MetricKit diagnostic kind this row represents, derived from its
  /// ``origin`` (the `error_logs.source` column), or `nil` for any non-MetricKit
  /// row (sync errors, changelog/outbox streams).
  public var metricKitDiagnosticKind: MetricKitDiagnosticFields.Kind? {
    origin.flatMap(MetricKitDiagnosticMapper.kind(forSource:))
  }

  /// True when this row is one of the MetricKit crash / hang / CPU / disk-write
  /// diagnostics — the rows a crash-scoped feed should keep.
  public var isMetricKitDiagnostic: Bool { metricKitDiagnosticKind != nil }
}
