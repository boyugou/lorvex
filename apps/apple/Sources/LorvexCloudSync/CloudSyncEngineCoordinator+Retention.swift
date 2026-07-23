import LorvexCore

extension CloudSyncEngineCoordinator {
  /// Run the local retention sweep under the same operation gate as sync,
  /// account adoption, cloud-data deletion, and storage cutovers.
  ///
  /// Retention touches the outbox, inbound debt, audit purge queue, and
  /// generation-staging fences. Serializing it here prevents an app-lifecycle
  /// refresh from changing that state while a CloudSync operation is suspended
  /// at a transport boundary. The active-outbox policy is deliberately resolved
  /// only after this operation owns the gate: a maintenance request can wait
  /// behind a temporary sync-off cutover that restores live mode before it
  /// releases the gate, and a pre-gate Boolean snapshot would then shed live
  /// transport debt. The database work stays off the caller's actor so a
  /// foreground refresh never performs the synchronous sweep on MainActor.
  public func runLocalRetentionMaintenance(
    sync: any EnvelopeSyncServicing,
    activeOutboxCapPolicy: @escaping @Sendable () async -> Bool
  ) async throws {
    try await withSerializedOperation {
      let includeActiveOutboxCap = await activeOutboxCapPolicy()
      try await Task.detached(priority: .utility) {
        try sync.runLocalRetentionMaintenance(
          includeActiveOutboxCap: includeActiveOutboxCap)
      }.value
    }
  }
}
