import AppIntents
import LorvexCore
import LorvexWidgetKitSupport

/// Opens the Lorvex app to Today, where the current focus plan lives.
///
/// Tap action for `LorvexFocusControlWidget`. Control Center runs the intent in
/// the widget-extension process, so it records a Today destination in the shared
/// App-Group handoff store (`LorvexIntentHandoffStore`); the app drains that
/// store on scene-active and navigates to Today on both cold launch and warm
/// resume.
@available(iOS 18.0, macOS 26.0, *)
public struct OpenLorvexFocusIntent: AppIntent, ControlConfigurationIntent {
  public static let title = LocalizedStringResource("widget.intent.focus.open.title", defaultValue: "Open Lorvex Focus", table: "Localizable", bundle: WidgetSupportL10n.bundle)

  public static let description = IntentDescription(LocalizedStringResource("widget.intent.focus.open.description", defaultValue: "Opens Lorvex to the current focus plan.", table: "Localizable", bundle: WidgetSupportL10n.bundle))
  public static let openAppWhenRun = true

  // A control-widget tap that opens the app: attended and navigation-only, so it
  // runs on the lock screen without authentication.
  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  // Opening the app is declared across two deployment bands. On iOS 26+ the
  // modern `supportedModes = .foreground` below is authoritative and brings the
  // app to the foreground. iOS 18–25 predate that API, so the deprecated
  // `openAppWhenRun = true` above is the mechanism there — it still functions
  // (soft deprecation) and is the era-correct way for a `ControlWidgetButton`
  // to open its app. Apple's deprecation caveat, that `openAppWhenRun` errors
  // when an intent is *run* inside an app extension, keys on the runtime
  // execution target rather than the host binary, and is resolved on iOS 26+ by
  // declaring `supportedModes`; the control opens the app on both bands.
  @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
  public static var supportedModes: IntentModes { .foreground }

  public init() {}

  @MainActor
  public func perform() async throws -> some IntentResult {
    LorvexIntentHandoffStore().storeDestination(SidebarSelection.today.rawValue)
    return .result()
  }
}
