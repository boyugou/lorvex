import Foundation
import LorvexCore

/// The error a Lorvex App Intent throws when the work behind it fails.
///
/// Shortcuts and Siri show a thrown error's own text. The core's errors carry
/// English sentences written for the MCP boundary, and a storage failure can
/// carry SQL or a file path, so none of them is fit to show as written. This
/// error holds the failure's ``UserFacingError`` classification and shows the
/// sentence the app shows for it, in the interface language: the app's own
/// wording for a failure it recognizes, "That item no longer exists." for a
/// lookup miss, or the generic "try again" line. The classification is the
/// original failure's, so classifying this error again still yields the
/// underlying category, reason, and technical detail.
public struct LorvexIntentFailure: LocalizedError, CustomLocalizedStringResourceConvertible,
  UserFacingClassifiedError
{
  public let userFacingClassification: UserFacingError.Classification

  /// Rewords `error`; a `LorvexIntentFailure` keeps its classification.
  public init(_ error: Error) {
    userFacingClassification = UserFacingError.classify(error)
  }

  /// The sentence Shortcuts and Siri show, in the interface language.
  public var message: String {
    UserFacingError.message(for: userFacingClassification, copy: .standard)
  }

  public var errorDescription: String? { message }

  public var localizedStringResource: LocalizedStringResource {
    LocalizedStringResource(stringLiteral: message)
  }
}

extension LorvexIntentFailure {
  /// Runs `work`, throwing its failure as a `LorvexIntentFailure`.
  ///
  /// Cancellation and an already reworded failure pass through unchanged. A
  /// failure the person sees only as generic copy — a lookup miss, a storage
  /// failure, an internal error, anything but a validation sentence — is also
  /// written to the diagnostics log through `core` with its technical detail,
  /// best effort, so a failed Siri or Shortcuts action can be traced.
  ///
  /// The whole run, the diagnostics write included, happens inside
  /// ``DatabaseSuspension/withBackgroundAccess(_:)``: the system runs an App
  /// Intent in a backgrounded process too, where the store's connection may
  /// still be suspended from the app's last trip to the background.
  static func rewording<Value>(
    core: any LorvexCoreServicing,
    _ work: () async throws -> Value
  ) async throws -> Value {
    try await DatabaseSuspension.withBackgroundAccess { () async throws -> Value in
      do {
        return try await work()
      } catch let cancellation as CancellationError {
        throw cancellation
      } catch let failure as LorvexIntentFailure {
        throw failure
      } catch {
        let failure = LorvexIntentFailure(error)
        if failure.userFacingClassification.category != .validation {
          try? await core.appendDiagnosticLog(
            source: "intent.action_failed", level: "error",
            message: "A Siri or Shortcuts action failed.",
            details: failure.userFacingClassification.technicalDetail)
        }
        throw failure
      }
    }
  }

  /// Runs synchronous `work`, throwing its failure as a `LorvexIntentFailure`.
  static func rewording<Value>(_ work: () throws -> Value) throws -> Value {
    do {
      return try work()
    } catch let failure as LorvexIntentFailure {
      throw failure
    } catch {
      throw LorvexIntentFailure(error)
    }
  }
}
