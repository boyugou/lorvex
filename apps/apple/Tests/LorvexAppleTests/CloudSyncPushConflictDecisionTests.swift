import Foundation
import Testing
import LorvexCloudSync
import LorvexDomain

// MARK: - Pure decision

/// HLC strings used as the contested versions. All share a device suffix so the
/// physical-ms / counter prefix is the sole ordering axis under test.
private func hlc(_ physical: Int, counter: Int = 0) -> String {
  String(format: "%013d_%04d_a1b2c3d4a1b2c3d4", physical, counter)
}

@Test
func conflictServerNewerWinsAndApplies() {
  // Failure timeline CK-01: server holds v5, our push carried v3 → the server
  // wins, the row is confirmed without overwriting the server, and the server
  // record is applied locally so this device converges on v5.
  let decision = resolveCloudSyncPushConflict(
    localVersion: hlc(3), serverVersion: hlc(5))
  #expect(decision == .serverWinsConfirmAndApply)
}

@Test
func conflictLocalNewerResavesOntoServer() {
  // server holds v3, our push carried v5 → local strictly wins, so the engine's
  // winner is re-stamped onto the server record and re-saved.
  let decision = resolveCloudSyncPushConflict(
    localVersion: hlc(5), serverVersion: hlc(3))
  #expect(decision == .localWinsResaveOntoServer)
}

@Test
func conflictEqualVersionsConfirmsWithoutResaveOrApply() {
  let decision = resolveCloudSyncPushConflict(
    localVersion: hlc(4), serverVersion: hlc(4))
  #expect(decision == .equalConfirm)
}

@Test
func conflictTieBreaksOnCounterThenSuffixViaHlcOrder() {
  // Same physical-ms; the counter is the next axis. Higher counter is newer.
  #expect(
    resolveCloudSyncPushConflict(
      localVersion: hlc(4, counter: 2), serverVersion: hlc(4, counter: 1))
      == .localWinsResaveOntoServer)
  #expect(
    resolveCloudSyncPushConflict(
      localVersion: hlc(4, counter: 1), serverVersion: hlc(4, counter: 2))
      == .serverWinsConfirmAndApply)
}

@Test
func conflictUnparseableLocalVersionFallsBackToServerWins() {
  // An unparseable local version cannot be proven to be the LWW winner, so the
  // conservative choice defers to the server rather than overwriting it.
  let decision = resolveCloudSyncPushConflict(
    localVersion: "not-an-hlc", serverVersion: hlc(5))
  #expect(decision == .serverWinsConfirmAndApply)
}

@Test
func conflictUnparseableServerVersionRequiresCorruptSlotRepair() {
  let decision = resolveCloudSyncPushConflict(
    localVersion: hlc(5), serverVersion: "garbage")
  #expect(decision == .corruptServerSlot)
}

@Test
func conflictParseableButNoncanonicalEqualServerVersionNeverConfirms() {
  let canonical = hlc(5, counter: 1)
  let unpaddedCounter = "0000000000005_1_a1b2c3d4a1b2c3d4"
  let canonicalHlc = try? Hlc.parse(canonical)
  #expect((try? Hlc.parse(unpaddedCounter)) == canonicalHlc)

  let decision = resolveCloudSyncPushConflict(
    localVersion: canonical, serverVersion: unpaddedCounter)

  #expect(decision == .corruptServerSlot)
  #expect(decision != .equalConfirm)
}
