import AppIntents

/// Central authentication-policy and execution-mode classification for Lorvex's
/// system App Intents.
///
/// App Intents are invokable from Shortcuts, Siri, Spotlight, and automations —
/// contexts that can run against a locked device. `AppIntent` defaults every
/// intent to `.alwaysAllowed` (runs on the lock screen) with no confirmation, so
/// an unclassified intent silently inherits the weakest posture. Each Lorvex
/// system intent therefore conforms to exactly one of the marker protocols
/// below, which pins its `authenticationPolicy`. A reviewer reads the tier off
/// the type's declaration, and `IntentSecurityClassificationTests` asserts the
/// resolved value so a new intent added as a bare `AppIntent` — or filed under
/// the wrong tier — trips a test.
///
/// Tiers:
/// - `LorvexUnauthenticatedIntent` (`.alwaysAllowed`): navigation and
///   append-only capture that are safe to run from the lock screen.
/// - `LorvexAuthenticatedIntent` (`.requiresAuthentication`): mutations and
///   metadata reads that require the device to be unlocked.
/// - `LorvexLocalAuthIntent` (`.requiresLocalDeviceAuthentication`):
///   content-returning reads and data exports that require on-device biometric
///   or passcode authentication before user content leaves the store.
///
/// All three inherit a `.background` execution mode from `LorvexSecuredIntent`;
/// navigation intents override to `.foreground`. `supportedModes` is only
/// modeled on macOS 26 / iOS 26 and later, so the `openAppWhenRun = false`
/// default below is the execution-mode witness on the deployment floor
/// (macOS 15 / iOS 18) — the framework derives the same background/foreground
/// split from it there, and the foreground navigation intents override it to
/// `true`.

/// Root marker: a Lorvex system intent that runs in the background by default.
protocol LorvexSecuredIntent: AppIntent {}

extension LorvexSecuredIntent {
  static var openAppWhenRun: Bool { false }

  @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
  static var supportedModes: IntentModes { .background }
}

/// Runs on the lock screen without authentication — navigation and append-only
/// capture only.
protocol LorvexUnauthenticatedIntent: LorvexSecuredIntent {}

extension LorvexUnauthenticatedIntent {
  static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }
}

/// Requires the device to be unlocked — mutations and low-sensitivity metadata
/// reads.
protocol LorvexAuthenticatedIntent: LorvexSecuredIntent {}

extension LorvexAuthenticatedIntent {
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
}

/// Requires on-device biometric/passcode authentication — content-returning
/// reads and data exports that move user content off the device.
protocol LorvexLocalAuthIntent: LorvexSecuredIntent {}

extension LorvexLocalAuthIntent {
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
}

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
