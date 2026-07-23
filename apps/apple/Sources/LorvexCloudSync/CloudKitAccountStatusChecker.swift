import Foundation
import LorvexCore
@preconcurrency import CloudKit

/// Maps CKAccountStatus to a Sendable type that can cross actor boundaries.
public enum CloudKitAccountAvailability: Equatable, Sendable {
  /// The account is available and sync operations may proceed.
  case available
  /// No iCloud account is signed in.
  case noAccount
  /// The account is restricted by parental controls or a device management profile.
  case restricted
  /// Account status could not be determined (network error, service unavailable).
  case couldNotDetermine
  /// The temporary token is unavailable (iOS-only; treated as couldNotDetermine on macOS).
  case temporarilyUnavailable

  public var userFacingMessage: String {
    switch self {
    case .available:
      return "iCloud account is available."
    case .noAccount:
      return "No iCloud account. Sign in via System Settings > Apple Account."
    case .restricted:
      return "iCloud is restricted by a device management profile."
    case .couldNotDetermine:
      return "Unable to determine iCloud account status."
    case .temporarilyUnavailable:
      return "iCloud account is temporarily unavailable."
    }
  }
}

/// Checks the CloudKit account status, abstracting `CKContainer` for testability.
public protocol CloudKitAccountStatusChecking: Sendable {
  func checkAccountStatus() async throws -> CloudKitAccountAvailability
}

/// Production implementation that queries the Lorvex CloudKit container.
public struct LiveCloudKitAccountStatusChecker: CloudKitAccountStatusChecking {
  private let containerIdentifier: String

  public init(containerIdentifier: String = LorvexProductMetadata.cloudKitContainerIdentifier) {
    self.containerIdentifier = containerIdentifier
  }

  public func checkAccountStatus() async throws -> CloudKitAccountAvailability {
    let status = try await CKContainer(identifier: containerIdentifier).accountStatus()
    return CloudKitAccountAvailability(from: status)
  }
}

public extension CloudKitAccountAvailability {
  init(from status: CKAccountStatus) {
    switch status {
    case .available: self = .available
    case .noAccount: self = .noAccount
    case .restricted: self = .restricted
    case .couldNotDetermine: self = .couldNotDetermine
    case .temporarilyUnavailable: self = .temporarilyUnavailable
    @unknown default: self = .couldNotDetermine
    }
  }
}
