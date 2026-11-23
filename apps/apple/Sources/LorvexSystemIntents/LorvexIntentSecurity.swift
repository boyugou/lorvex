import AppIntents

/// The security tier of each Lorvex system App Intent.
///
/// App Intents are invokable from Shortcuts, Siri, Spotlight, and automations,
/// contexts that can run against a locked device. `AppIntent` defaults every
/// intent to `.alwaysAllowed` (runs on the lock screen) with no confirmation, so
/// an unclassified intent silently takes the weakest posture. Each Lorvex
/// system intent therefore declares its `authenticationPolicy` in its own
/// body, and every intent a person or an automation invokes names exactly one
/// of the tier protocols below, which says which policy that is. The Focus
/// filter, which the system applies when a Focus turns on, names no tier and
/// declares `.alwaysAllowed`.
///
/// - `LorvexUnauthenticatedIntent`, `.alwaysAllowed`: navigation and
///   append-only capture that are safe to run from the lock screen.
/// - `LorvexAuthenticatedIntent`, `.requiresAuthentication`: mutations and
///   metadata reads that require the device to be unlocked.
/// - `LorvexLocalAuthIntent`, `.requiresLocalDeviceAuthentication`:
///   content-returning reads and data exports that require on-device biometric
///   or passcode authentication before user content leaves the store.
///
/// The policy is declared in each intent, as a `static let` with a literal
/// value, because the build's App Intents metadata step reads only what a type
/// declares itself. A value a protocol extension supplies never reaches the
/// metadata, which then records the intent as `.alwaysAllowed`. The tier
/// protocol names the tier and supplies no policy. `verify_system_entrypoints.py`
/// fails when an intent declares no policy, names more than one tier, or
/// declares a policy that is not its tier's, and the Mac build's metadata step
/// fails when an action reaches the metadata without a declared policy.
/// `IntentSecurityClassificationTests` asserts the run-time value for a sample
/// of intents in each tier.
///
/// All three tiers take a `.background` execution mode from
/// `LorvexSecuredIntent`, which is also the framework's default, so the
/// metadata agrees without a declaration. The foreground navigation intents
/// declare `.foreground` and `openAppWhenRun = true` themselves.

/// Root marker: a Lorvex system intent that runs in the background by default.
protocol LorvexSecuredIntent: AppIntent {}

extension LorvexSecuredIntent {
  static var openAppWhenRun: Bool { false }

  @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, *)
  static var supportedModes: IntentModes { .background }
}

/// Runs on the lock screen without authentication: navigation and append-only
/// capture only. A conforming intent declares
/// `static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed`.
protocol LorvexUnauthenticatedIntent: LorvexSecuredIntent {}

/// Requires the device to be unlocked: mutations and low-sensitivity metadata
/// reads. A conforming intent declares
/// `static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication`.
protocol LorvexAuthenticatedIntent: LorvexSecuredIntent {}

/// Requires on-device biometric or passcode authentication: content-returning
/// reads and data exports that move user content off the device. A conforming
/// intent declares `static let authenticationPolicy: IntentAuthenticationPolicy =
/// .requiresLocalDeviceAuthentication`.
protocol LorvexLocalAuthIntent: LorvexSecuredIntent {}

extension AppIntent {
  /// Prompts the user to approve a destructive Lorvex mutation before it runs.
  ///
  /// Presents `dialog` on the confirmation request so an attended run always
  /// surfaces a prompt. An unattended Shortcuts automation escalates the same
  /// request to a notification the user must approve; the mutation never
  /// proceeds unconfirmed. Throwing out of this call (the user declined or
  /// dismissed the prompt) aborts `perform()` before any store write. This
  /// confirmation gate is complementary to `authenticationPolicy`:
  /// authentication proves *who* is running the intent, confirmation proves the
  /// destructive effect is *intended*.
  func requestLorvexDestructiveConfirmation(_ dialog: IntentDialog) async throws {
    try await requestConfirmation(actionName: .continue, dialog: dialog)
  }
}
