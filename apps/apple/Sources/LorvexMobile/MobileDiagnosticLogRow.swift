import LorvexCore
import LorvexDomain
import SwiftUI

/// Read-only row for one entry in the crash-scoped diagnostics feed. Takes a
/// plain ``RecentLogEntry`` and the current instant for relative timestamping,
/// never the store. A leading level glyph (MetricKit crashes/hangs read as
/// `error`), a source-derived kind eyebrow (Crash / Hang / CPU / Disk Write,
/// from ``RecentLogEntry/origin``), the one-line summary, an abbreviated
/// relative time, and the optional sanitized detail line.
struct MobileDiagnosticLogRow: View {
  let entry: RecentLogEntry
  let now: Date

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: glyph)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        if let kindLabel {
          Text(kindLabel)
            .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(tint)
        }
        Text(entry.summary)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
        if let details = entry.details, !details.isEmpty {
          Text(details)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .truncationMode(.middle)
        }
        if let relative = relativeTimestamp {
          Text(relative)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.tertiary)
        }
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("mobileDiagnostics.log.\(entry.id)")
  }

  /// Localized crash-kind eyebrow derived from the row's `error_logs.source`
  /// (via ``RecentLogEntry/origin``), or `nil` for a non-MetricKit row.
  private var kindLabel: String? {
    switch entry.metricKitDiagnosticKind {
    case .crash:
      return String(
        localized: "diagnostics.kind.crash", defaultValue: "Crash", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .hang:
      return String(
        localized: "diagnostics.kind.hang", defaultValue: "Hang", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .cpuException:
      return String(
        localized: "diagnostics.kind.cpu", defaultValue: "CPU", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .diskWriteException:
      return String(
        localized: "diagnostics.kind.disk", defaultValue: "Disk Write", table: "Localizable",
        bundle: MobileL10n.bundle)
    case nil: return nil
    }
  }

  private var glyph: String {
    switch entry.level {
    case .error: return "exclamationmark.triangle.fill"
    case .warn: return "exclamationmark.circle.fill"
    case .debug: return "ladybug"
    case .info: return "info.circle"
    }
  }

  private var tint: Color {
    switch entry.level {
    case .error: return .red
    case .warn: return .orange
    case .debug, .info: return .secondary
    }
  }

  private var relativeTimestamp: String? {
    guard let timestamp = entry.timestamp, let date = Self.parse(timestamp) else { return nil }
    return MobileDateFormatting.abbreviatedRelativeString(for: date, relativeTo: now)
  }

  /// Parse the merged feed's ISO-8601 timestamps, tolerating both the core's
  /// millisecond-`Z` shape (`2026-07-02T09:41:00.123Z`) and the plain
  /// second-resolution form the preview backend emits.
  private static func parse(_ value: String) -> Date? {
    LorvexDateFormatters.iso8601Fractional.date(from: value)
      ?? ISO8601DateFormatter().date(from: value)
  }

  private var accessibilityLabel: String {
    var label = entry.summary
    if let kindLabel { label = "\(kindLabel): \(label)" }
    if let relative = relativeTimestamp { label += ", \(relative)" }
    return label
  }
}
