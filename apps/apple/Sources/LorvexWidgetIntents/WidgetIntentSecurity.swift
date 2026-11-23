import AppIntents

/// The security posture of Lorvex's interactive widget-tap intents.
///
/// These intents are constructed with an id baked into the widget's render
/// model and are invoked by an attended tap on a widget the user is already
/// looking at, so they are `.alwaysAllowed` (a lock-screen or StandBy widget
/// tap must still act). They are not discoverable: they are a widget
/// affordance, not an action a person composes in Shortcuts or asks Siri for,
/// and the composable actions live in `LorvexSystemIntents`.
///
/// A conforming intent declares both in its own body, as `static let` with
/// literal values, because the build's App Intents metadata step reads only
/// what a type declares itself:
///
///     public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
///     public static let isDiscoverable: Bool = false
///
/// `verify_system_entrypoints.py` fails when either is missing. The intents
/// run in the widget-extension process in the background, which is also the
/// framework's default.
public protocol LorvexWidgetActionIntent: AppIntent {}

extension LorvexWidgetActionIntent {
  public static var openAppWhenRun: Bool { false }

  @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, *)
  public static var supportedModes: IntentModes { .background }
}
