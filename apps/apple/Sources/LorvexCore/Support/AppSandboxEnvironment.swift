import Foundation
#if os(macOS)
import Security
#endif

/// Detects whether the current process is confined to an App Sandbox
/// container, at runtime.
///
/// The authoritative signal is the running process's own signed
/// `com.apple.security.app-sandbox` entitlement, read through the Security
/// framework (`SecTaskCopyValueForEntitlement`) — the same mechanism
/// `AppGroupAccess` uses for the App Group entitlement. The kernel enforces the
/// sandbox from that signed entitlement, so it is the true property of "is this
/// build sandboxed right now," independent of distribution channel: both of
/// Lorvex's signed macOS entitlement files (`LorvexApple.entitlements` and the
/// App Store variant) grant it; an ad-hoc/unsigned local build (`swift run`, or
/// packaging with `CODE_SIGN_IDENTITY=-`, which drops entitlements entirely)
/// does not — and that unsigned case is the only one that honors the
/// `LORVEX_APPLE_DB_PATH` dev database override.
///
/// The `APP_SANDBOX_CONTAINER_ID` environment variable is only a *fallback*,
/// consulted when the signed entitlement cannot be read (an unsigned/ad-hoc
/// build, or a test process). macOS sets that variable for every sandboxed
/// process, but it is not a documented application-facing contract, so it does
/// not decide the storage policy on its own: keying off the signed entitlement
/// keeps a spoofed, missing, or externally injected variable from selecting the
/// wrong storage contract (dev-override-vs-managed) for a process whose real
/// sandbox state the kernel already fixed.
///
/// The entitlement read is gated to macOS — the only platform where the
/// sandboxed-vs-unsandboxed distinction changes the storage decision (the
/// `LORVEX_APPLE_DB_PATH` dev override is a macOS-only, unsandboxed-build
/// feature). iOS/iPadOS/visionOS/watchOS/tvOS builds are always sandboxed and
/// always open the Lorvex-managed store, so those platforms fail closed without
/// consulting a macOS-specific environment variable or the Security framework.
///
/// Deliberately not a compile-time `#if` flag for the sandbox itself: a single
/// macOS binary is signed and sandboxed differently across dev/local/
/// Developer-ID/MAS builds, so only a runtime check distinguishes them
/// correctly.
///
/// Shared by the main app and the MCP helper (each deciding whether to honor the
/// `LORVEX_APPLE_DB_PATH` dev override) so the two processes cannot disagree
/// about whether the environment they are running in is sandboxed.
public enum AppSandboxEnvironment {
  public static let sandboxEntitlementKey = "com.apple.security.app-sandbox"

  /// The current process's signed `com.apple.security.app-sandbox` entitlement:
  /// `true`/`false` when the entitlement is present and boolean, `nil` when it
  /// is absent or the code-signing information cannot be read (unsigned/ad-hoc
  /// builds, test processes, and every non-macOS platform). `nil` means "no
  /// authoritative signal — fall back to the environment variable."
  public static func signedSandboxEntitlement() -> Bool? {
    #if os(macOS)
    guard let task = SecTaskCreateFromSelf(nil),
      let value = SecTaskCopyValueForEntitlement(task, sandboxEntitlementKey as CFString, nil)
    else {
      return nil
    }
    if let boolValue = value as? Bool {
      return boolValue
    }
    if let number = value as? NSNumber {
      return number.boolValue
    }
    return nil
    #else
    return nil
    #endif
  }

  /// Whether this process is confined to an App Sandbox container.
  ///
  /// Consults the signed entitlement first (`signedEntitlement`); only when that
  /// returns `nil` does it fall back to the `APP_SANDBOX_CONTAINER_ID`
  /// environment variable. `signedEntitlement` is injected so callers can test
  /// the resolution logic deterministically without a signed binary.
  public static func isSandboxed(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    signedEntitlement: () -> Bool? = signedSandboxEntitlement
  ) -> Bool {
    isSandboxed(
      environment: environment,
      platformRequiresSandbox: platformRequiresSandbox,
      signedEntitlement: signedEntitlement)
  }

  /// Resolution seam for deterministic cross-platform policy tests. Mobile
  /// Apple platforms cannot opt out of the sandbox, so their compile-time
  /// platform contract takes precedence over every runtime signal.
  static func isSandboxed(
    environment: [String: String],
    platformRequiresSandbox: Bool,
    signedEntitlement: () -> Bool?
  ) -> Bool {
    if platformRequiresSandbox {
      return true
    }
    if let entitled = signedEntitlement() {
      return entitled
    }
    return !(environment["APP_SANDBOX_CONTAINER_ID"] ?? "").isEmpty
  }

  private static var platformRequiresSandbox: Bool {
    #if os(iOS) || os(visionOS) || os(watchOS) || os(tvOS)
    return true
    #else
    return false
    #endif
  }
}
