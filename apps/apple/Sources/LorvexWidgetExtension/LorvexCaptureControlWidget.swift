import AppIntents
import LorvexCore
import LorvexWidgetIntents
import LorvexWidgetKitSupport
import SwiftUI
import WidgetKit

/// Control Center and Lock Screen button that opens Lorvex with the capture
/// sheet ready for a new task.
///
/// The control shows no task data, so it needs no snapshot and no reload: it is
/// the same action as the Home Screen's Quick Capture, one tap from anywhere.
/// Tapping runs `OpenLorvexCaptureIntent`.
///
/// Requires iOS 18. The Mac's capture entry points are the Quick Capture window
/// and its shortcut, so the control is registered on iOS only.
@available(iOS 18.0, macOS 26.0, *)
public struct LorvexCaptureControlWidget: ControlWidget {
  public static let kind = "com.lorvex.control.capture"

  public init() {}

  public var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind) {
      ControlWidgetButton(action: OpenLorvexCaptureIntent()) {
        Label {
          Text(
            LocalizedStringResource(
              "widget.control.capture.label", defaultValue: "Quick Capture",
              table: "Localizable", bundle: WidgetSupportL10n.bundle))
        } icon: {
          Image(systemName: LorvexQuickAction.quickCapture.systemImageName)
        }
      }
    }
    .displayName(
      LocalizedStringResource(
        "widget.control.capture.display_name", defaultValue: "Lorvex Capture",
        table: "Localizable", bundle: WidgetSupportL10n.bundle)
    )
    .description(
      LocalizedStringResource(
        "widget.control.capture.description", defaultValue: "Opens Lorvex ready to add a task.",
        table: "Localizable", bundle: WidgetSupportL10n.bundle))
  }
}
