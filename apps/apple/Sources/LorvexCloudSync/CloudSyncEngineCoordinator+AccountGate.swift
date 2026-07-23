import Foundation
import LorvexCore
import LorvexSync
import os

enum AccountIdentityComparison: Sendable, Equatable {
  case sameAccount
  case differentAccount
  case unconfirmable
}

extension CloudSyncEngineCoordinator {
  private static let gateLog = Logger(
    subsystem: "com.lorvex.apple", category: "cloudsync")

  enum AccountStartGateDecision: Sendable, Equatable {
    case halt
    case proceed
  }

  private func compareToRecordedIdentity(
    stored: String
  ) async -> AccountIdentityComparison {
    guard let current = await accountIdentifier.currentAccountIdentifier() else {
      return .unconfirmable
    }
    return current == stored ? .sameAccount : .differentAccount
  }

  /// Fail-closed account boundary evaluated before any generation read/write.
  /// First binding persists the live account before the cycle starts; a switch
  /// never self-adopts and requires the explicit consent path.
  func passesAccountStartGate(
    sync: any EnvelopeSyncServicing
  ) async -> AccountStartGateDecision {
    let stored: String?
    let pause: CloudSyncPauseSnapshot?
    do {
      stored = try await accountIdentityStore.loadLastAccountIdentifier()
      pause = try await accountPauseStore.loadPauseSnapshot()
    } catch {
      Self.gateLog.error(
        "CloudSync account gate state is unreadable; halting: \(error.localizedDescription, privacy: .private)")
      return .halt
    }

    if let pause {
      switch pause.reason {
      case .adoptionInProgress, .backfillFailed, .userDeletedZone:
        return .halt
      case .accountChanged:
        break
      }
    }

    guard let current = await accountIdentifier.currentAccountIdentifier() else {
      return .halt
    }

    // SQLite is the account lineage authority because its binding commits with
    // traversal proofs and survives a database restore. The external identity
    // file is only a repairable launch gate; never let its absence turn a DB
    // already bound to A into a false first binding for live account B.
    let sourceBinding: CloudTraversalAccountBinding?
    do {
      _ = try sync.databaseInstanceIdentifier()
      sourceBinding = try sync.cloudTraversalAccountBindingForAdoption()
    } catch {
      Self.gateLog.error(
        "CloudSync could not resolve the SQLite account lineage; halting: \(error.localizedDescription, privacy: .private)")
      return .halt
    }

    if let sourceBinding {
      if stored != sourceBinding.accountIdentifier {
        do {
          try await accountIdentityStore.saveLastAccountIdentifier(
            sourceBinding.accountIdentifier)
        } catch { return .halt }
      }
      guard current == sourceBinding.accountIdentifier else {
        do {
          try await accountPauseStore.setPauseReasonPreservingUserDeletedZone(
            .accountChanged)
        } catch {
          Self.gateLog.error(
            "CloudSync could not persist the SQLite account-boundary pause: \(error.localizedDescription, privacy: .private)")
        }
        return .halt
      }
      if let pause {
        do {
          guard case .applied(nil) =
            try await accountPauseStore.compareAndSetPauseSnapshot(
              expected: pause, replacement: nil)
          else { return .halt }
        } catch { return .halt }
      }
      return .proceed
    }

    guard let stored else {
      do {
        try await accountIdentityStore.saveLastAccountIdentifier(current)
        // A CKAccountChanged edge may have observed an unavailable identity
        // immediately before this device's first account appeared. Only the
        // fresh, unbound database branch can prove that this is not an account
        // switch. Consume exactly the pause snapshot read at the gate's start;
        // a concurrent/newer pause remains authoritative and halts this cycle.
        if let pause {
          guard pause.reason == .accountChanged,
            case .applied(nil) =
              try await accountPauseStore.compareAndSetPauseSnapshot(
                expected: pause, replacement: nil)
          else { return .halt }
        }
        return .proceed
      } catch { return .halt }
    }

    switch current == stored ? AccountIdentityComparison.sameAccount : .differentAccount {
    case .sameAccount:
      if let pause {
        do {
          guard case .applied(nil) =
            try await accountPauseStore.compareAndSetPauseSnapshot(
              expected: pause, replacement: nil)
          else { return .halt }
        } catch { return .halt }
      }
      return .proceed
    case .differentAccount:
      do {
        try await accountPauseStore.setPauseReasonPreservingUserDeletedZone(
          .accountChanged)
      } catch {
        Self.gateLog.error(
          "CloudSync could not persist the account-switch pause; the identity mismatch still halts the cycle: \(error.localizedDescription, privacy: .private)")
      }
      return .halt
    case .unconfirmable:
      return .halt
    }
  }

  /// Mid-cycle recheck used after an externally suspended CloudKit request.
  func accountStillMatchesStartGate(context: String) async -> Bool {
    do {
      if try await accountPauseStore.loadPauseReason() != nil { return false }
      guard let stored = try await accountIdentityStore.loadLastAccountIdentifier()
      else { return false }
      switch await compareToRecordedIdentity(stored: stored) {
      case .sameAccount:
        return true
      case .unconfirmable:
        return false
      case .differentAccount:
        _ = try? await accountPauseStore.setPauseReasonPreservingUserDeletedZone(
          .accountChanged)
        Self.gateLog.notice(
          "CloudSync detected an account transition during \(context, privacy: .public)")
        return false
      }
    } catch {
      return false
    }
  }

  public func currentPauseReason() async -> CloudSyncPauseReason? {
    ((try? await accountPauseStore.loadPauseReason()) ?? nil)
  }
}
