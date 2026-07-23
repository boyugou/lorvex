import AppIntents

/// Security posture shared by Lorvex's interactive widget-tap intents.
///
/// These intents are constructed with an id baked into the widget's render
/// model and are invoked by an attended tap on a widget the user is already
/// looking at, so they keep `.alwaysAllowed` authentication (a lock-screen /
/// StandBy widget tap must still act). `isDiscoverable = false` keeps them out
/// of the general Shortcuts/Siri action list — they are a widget affordance, not
/// a user-composable action, and the equivalent composable actions live in
/// `LorvexSystemIntents`. They run in the widget-extension process
/// (`.background`); `supportedModes` is only modeled on macOS 26 / iOS 26 and
/// later, so `openAppWhenRun = false` remains the execution-mode witness on the
/// deployment floor.
public protocol LorvexWidgetActionIntent: AppIntent {}

extension LorvexWidgetActionIntent {
  public static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }
  public static var isDiscoverable: Bool { false }
  public static var openAppWhenRun: Bool { false }

  @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
  public static var supportedModes: IntentModes { .background }
}
