import Foundation
import LorvexCore

/// Typed host boundary for a user-confirmed data restore.
///
/// Live sync must absorb and prove the current CloudKit generation before the
/// importer's first presence/tombstone decision. Non-live modes deliberately do
/// no CloudKit I/O, but still share the retained coordinator gate when one is
/// available so a concurrent mode transition or cloud-maintenance action has a
/// deterministic order relative to the multi-record restore.
public enum CloudSyncDataImportBoundary {
  public struct Result: Sendable, Equatable {
    public let summary: LorvexImportSummary
    public let preImportSyncReport: CloudSyncCycleReport?
    public let postTerminalSyncFailure: CloudSyncPostTerminalFailure?

    public init(
      summary: LorvexImportSummary,
      preImportSyncReport: CloudSyncCycleReport?,
      postTerminalSyncFailure: CloudSyncPostTerminalFailure? = nil
    ) {
      self.summary = summary
      self.preImportSyncReport = preImportSyncReport
      self.postTerminalSyncFailure = postTerminalSyncFailure
    }
  }

  public enum BoundaryError: Error, LocalizedError, Sendable, Equatable {
    case importAlreadyRunning
    case dataMaintenanceRunning
    case liveCoordinatorUnavailable
    case cloudSyncRetryDeferred

    public var errorDescription: String? {
      switch self {
      case .importAlreadyRunning:
        "Another data import is already running."
      case .dataMaintenanceRunning:
        "Another data maintenance operation is already running."
      case .liveCoordinatorUnavailable:
        "The live iCloud synchronization service is unavailable."
      case .cloudSyncRetryDeferred:
        "iCloud synchronization is waiting before its next retry."
      }
    }
  }

  /// Cancellation is control flow, not a CloudKit transport failure. A drain
  /// may wrap it after committing an inbound prefix, so hosts still adopt that
  /// report but must not advance failure pacing or replace the last sync error.
  public static func isCancellation(_ error: any Error) -> Bool {
    if error is CancellationError { return true }
    if let partial = error as? CloudSyncPartialCycleFailure {
      return partial.underlyingError is CancellationError
    }
    return false
  }

  /// A confirmed restore is an explicit foreground action, so it gets one
  /// immediate attempt even when ordinary background triggers are inside their
  /// local exponential backoff. `CloudSyncPacing.reset()` deliberately keeps a
  /// server-provided retry-after deadline intact; that deadline still defers the
  /// restore rather than allowing user retries to stampede CloudKit.
  public static func beginLivePreflightIfNeeded(
    mode: CloudSyncMode,
    pacing: inout CloudSyncPacing,
    now: Date
  ) throws -> Date? {
    guard mode == .live else { return nil }
    pacing.reset()
    guard pacing.shouldRun(now: now) else {
      throw BoundaryError.cloudSyncRetryDeferred
    }
    pacing.recordAttempt(now: now)
    return now
  }

  public static func apply(
    plan: LorvexImportPlan,
    decoded: LorvexDataImporter.DecodedImport,
    using core: any LorvexCoreServicing,
    mode: CloudSyncMode,
    liveCoordinator: CloudSyncEngineCoordinator?,
    maintenanceCoordinator: CloudSyncEngineCoordinator?
  ) async throws -> Result {
    let importOperation: @Sendable () async -> LorvexImportSummary = {
      await LorvexDataImporter.apply(plan: plan, decoded: decoded, using: core)
    }

    switch mode {
    case .live:
      guard let liveCoordinator else {
        throw BoundaryError.liveCoordinatorUnavailable
      }
      let operation = try await liveCoordinator.withTerminalInboundDrain(
        core: core, operation: importOperation)
      return Result(
        summary: operation.value,
        preImportSyncReport: operation.drainReport,
        postTerminalSyncFailure: operation.postTerminalSyncFailure)

    case .off, .recordPlan:
      let summary: LorvexImportSummary
      if let maintenanceCoordinator {
        summary = try await maintenanceCoordinator.withQuiescedCloudSync(importOperation)
      } else {
        summary = await importOperation()
      }
      return Result(
        summary: summary,
        preImportSyncReport: nil,
        postTerminalSyncFailure: nil)
    }
  }
}
