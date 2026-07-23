import AppIntents
import Foundation
import LorvexCore
import LorvexWidgetIntents
import LorvexWidgetKitSupport
import SwiftUI
import WidgetKit

/// Control Center widget that shows the first active focus task title.
///
/// Displays the title of the first task in `focusTasks` from the shared App
/// Group snapshot. A genuinely empty plan shows "No focus"; a missing, broken,
/// or expired snapshot shows an explicit unavailable state. Tapping opens the
/// app to Today (where the focus plan lives) via `OpenLorvexFocusIntent`.
///
/// Requires iOS 18 / macOS 26 (Tahoe). The widget is additive and does not
/// raise the package minimum deployment target.
@available(iOS 18.0, macOS 26.0, *)
public struct LorvexFocusControlWidget: ControlWidget {
  public static let kind = LorvexProductMetadata.controlWidgetKind

  public init() {}

  public var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(
      kind: Self.kind,
      provider: LorvexFocusControlProvider()
    ) { value in
      ControlWidgetButton(action: OpenLorvexFocusIntent()) {
        if value.containsPrivateContent {
          // A focus-task title is private content on the Lock Screen / Control
          // Center. Empty and unavailable copy is non-sensitive and remains
          // readable while the device is locked.
          Label(value.title, systemImage: value.systemImage)
            .privacySensitive()
        } else {
          Label(value.title, systemImage: value.systemImage)
        }
      }
    }
    .displayName(
      LocalizedStringResource(
        "widget.control.display_name", defaultValue: "Lorvex Focus", table: "Localizable",
        bundle: WidgetSupportL10n.bundle)
    )
    .description(
      LocalizedStringResource(
        "widget.control.description", defaultValue: "Shows the current focus task.",
        table: "Localizable", bundle: WidgetSupportL10n.bundle))
  }
}

// MARK: - Value Provider

@available(iOS 18.0, macOS 26.0, *)
struct LorvexFocusControlValue: Equatable, Sendable {
  var title: String
  var systemImage: String
  var availability: FocusGlancePresentation.Availability

  var containsPrivateContent: Bool { availability == .content }

  static var preview: Self {
    .init(
      title: String(
        localized: "widget.control.preview.task_title",
        defaultValue: "Review spec",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle),
      systemImage: "timer",
      availability: .content)
  }

  static func from(
    snapshot: WidgetSnapshot?,
    now: Date,
    calendar: Calendar = .autoupdatingCurrent
  ) -> Self {
    let result =
      snapshot.map(WidgetSnapshotLoadResult.snapshot)
      ?? .fallback(.init(reason: .missingFile, detail: "Snapshot unavailable"))
    return from(result: result, now: now, calendar: calendar)
  }

  static func from(
    result: WidgetSnapshotLoadResult,
    now: Date,
    calendar: Calendar = .autoupdatingCurrent
  ) -> Self {
    let presentation = FocusGlancePresentation.resolve(
      from: result, now: now, calendar: calendar)
    switch presentation.availability {
    case .unavailable:
      return .init(
        title: String(
          localized: "widget.status.snapshot_unavailable",
          defaultValue: "Snapshot unavailable",
          table: "Localizable",
          bundle: WidgetSupportL10n.bundle),
        systemImage: "exclamationmark.circle",
        availability: .unavailable)
    case .empty:
      return .init(
        title: String(
          localized: "widget.control.no_focus",
          defaultValue: "No focus",
          table: "Localizable",
          bundle: WidgetSupportL10n.bundle),
        systemImage: "scope",
        availability: .empty)
    case .content:
      guard let first = presentation.primaryTask else {
        // `FocusGlancePresentation` guarantees a primary task for `.content`.
        // Keep this boundary total in case the projection evolves independently.
        return .init(
          title: String(
            localized: "widget.status.snapshot_unavailable",
            defaultValue: "Snapshot unavailable",
            table: "Localizable",
            bundle: WidgetSupportL10n.bundle),
          systemImage: "exclamationmark.circle",
          availability: .unavailable)
      }
      return .init(title: first.title, systemImage: "timer", availability: .content)
    }
  }
}

@available(iOS 18.0, macOS 26.0, *)
private struct LorvexFocusControlProvider: ControlValueProvider {
  typealias Value = LorvexFocusControlValue

  var previewValue: LorvexFocusControlValue {
    .preview
  }

  func currentValue() async throws -> LorvexFocusControlValue {
    focusValue(from: LorvexWidgetConfiguration().resolvedSnapshotURL(), now: Date())
  }

  // MARK: Private

  private func focusValue(from url: URL?, now: Date) -> LorvexFocusControlValue {
    guard let url else {
      return .from(
        result: .fallback(.init(reason: .missingFile, detail: "app_group_unavailable")),
        now: now)
    }
    let result = WidgetSnapshotLoader().loadSnapshot(at: url)
    return .from(result: result, now: now)
  }
}
