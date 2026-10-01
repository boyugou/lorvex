import AppIntents
import Foundation
import LorvexCore
import LorvexWidgetIntents
import LorvexWidgetKitSupport
import SwiftUI
import WidgetKit

/// Control Center button that names the task at the top of Today.
///
/// Shows the ``TodayLead`` of the shared App Group snapshot: a task whose time
/// is running, else the first task on Today. A day with nothing left shows
/// "All clear"; a missing, broken, or expired snapshot shows an explicit
/// unavailable state. Tapping opens the app to Today via
/// `OpenLorvexTodayIntent`.
///
/// Requires iOS 18 / macOS 26 (Tahoe). The widget is additive and does not
/// raise the package minimum deployment target.
@available(iOS 18.0, macOS 26.0, *)
public struct LorvexTodayControlWidget: ControlWidget {
  public static let kind = LorvexProductMetadata.controlWidgetKind

  public init() {}

  public var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(
      kind: Self.kind,
      provider: LorvexTodayControlProvider()
    ) { value in
      ControlWidgetButton(action: OpenLorvexTodayIntent()) {
        if value.containsPrivateContent {
          // A task title is private content on the Lock Screen / Control
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
        "widget.control.display_name", defaultValue: "Lorvex Today", table: "Localizable",
        bundle: WidgetSupportL10n.bundle)
    )
    .description(
      LocalizedStringResource(
        "widget.control.description", defaultValue: "Shows the task at the top of Today.",
        table: "Localizable", bundle: WidgetSupportL10n.bundle))
  }
}

// MARK: - Value Provider

@available(iOS 18.0, macOS 26.0, *)
struct LorvexTodayControlValue: Equatable, Sendable {
  var title: String
  var systemImage: String
  var availability: TodayGlancePresentation.Availability

  var containsPrivateContent: Bool { availability == .content }

  static var preview: Self {
    .init(
      title: String(
        localized: "widget.control.preview.task_title",
        defaultValue: "Review spec",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle),
      systemImage: "circle",
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
    let presentation = TodayGlancePresentation.resolve(
      from: result, now: now, calendar: calendar)
    switch presentation.availability {
    case .unavailable:
      return unavailable
    case .empty:
      return .init(
        title: String(
          localized: "widget.control.all_clear",
          defaultValue: "All clear",
          table: "Localizable",
          bundle: WidgetSupportL10n.bundle),
        systemImage: "checkmark.circle",
        availability: .empty)
    case .content:
      guard let lead = presentation.lead else {
        // Tasks are left but none leads: say how many, not which.
        return .init(
          title: String(
            localized: "widget.day.left",
            defaultValue: "\(presentation.remainingCount) left today",
            table: "Localizable",
            bundle: WidgetSupportL10n.bundle),
          systemImage: "list.bullet",
          availability: .content)
      }
      return .init(title: lead.title, systemImage: "circle", availability: .content)
    }
  }

  private static var unavailable: Self {
    .init(
      title: String(
        localized: "widget.status.snapshot_unavailable",
        defaultValue: "Snapshot unavailable",
        table: "Localizable",
        bundle: WidgetSupportL10n.bundle),
      systemImage: "exclamationmark.circle",
      availability: .unavailable)
  }
}

@available(iOS 18.0, macOS 26.0, *)
private struct LorvexTodayControlProvider: ControlValueProvider {
  typealias Value = LorvexTodayControlValue

  var previewValue: LorvexTodayControlValue {
    .preview
  }

  func currentValue() async throws -> LorvexTodayControlValue {
    todayValue(from: LorvexWidgetConfiguration().resolvedSnapshotURL(), now: Date())
  }

  // MARK: Private

  private func todayValue(from url: URL?, now: Date) -> LorvexTodayControlValue {
    guard let url else {
      return .from(
        result: .fallback(.init(reason: .missingFile, detail: "app_group_unavailable")),
        now: now)
    }
    let result = WidgetSnapshotLoader().loadSnapshot(at: url)
    return .from(result: result, now: now)
  }
}
