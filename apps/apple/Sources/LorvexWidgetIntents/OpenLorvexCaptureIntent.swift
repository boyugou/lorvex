import AppIntents
import LorvexCore
import LorvexWidgetKitSupport

/// Opens the Lorvex app with the capture sheet ready for a new task.
///
/// Tap action for `LorvexCaptureControlWidget`. Control Center runs the intent in
/// the widget-extension process, so it records a Quick Capture request in the
/// shared App-Group handoff store (`LorvexIntentHandoffStore`); the app drains
/// that store on scene-active and presents the capture sheet on both cold launch
/// and warm resume, as it does for the Home Screen's Quick Capture action.
@available(iOS 18.0, macOS 26.0, *)
public struct OpenLorvexCaptureIntent: AppIntent, ControlConfigurationIntent {
  public static let title = LocalizedStringResource(
    "widget.intent.capture.open.title", defaultValue: "Quick Capture", table: "Localizable",
    bundle: WidgetSupportL10n.bundle)

  public static let description = IntentDescription(
    LocalizedStringResource(
      "widget.intent.capture.open.description", defaultValue: "Opens Lorvex ready to add a task.",
      table: "Localizable", bundle: WidgetSupportL10n.bundle))
  public static let openAppWhenRun = true

  // A control-widget tap that opens the app: attended and navigation-only, so it
  // runs on the lock screen without authentication. The app itself stays behind
  // the device's lock.
  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  // Opening the app is declared across two deployment bands, as on
  // `OpenLorvexTodayIntent`: `supportedModes = .foreground` is authoritative on
  // iOS 26+, and the deprecated `openAppWhenRun` is the mechanism on iOS 18–25.
  @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, *)
  public static var supportedModes: IntentModes { .foreground }

  public init() {}

  @MainActor
  public func perform() async throws -> some IntentResult {
    LorvexIntentHandoffStore().storeQuickAction(.quickCapture)
    return .result()
  }
}
