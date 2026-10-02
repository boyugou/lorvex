import LorvexCore
import LorvexDomain
import SwiftUI

/// Read-only row for one entry in the diagnostics failure feed. Takes a plain
/// ``RecentLogEntry`` and the current instant for relative timestamping, never
/// the store. A leading level glyph (MetricKit crashes/hangs read as `error`),
/// an eyebrow naming where the row came from, the one-line summary, an
/// abbreviated relative time, and the sanitized detail line.
///
/// The detail line is the diagnostic payload — a CloudKit transport message, a
/// classified exception — and is the reason this row exists, so it is truncated
/// only until tapped: tapping expands it in full and makes it selectable, which
/// is the only way to get the text off the device and into a bug report.
struct MobileDiagnosticLogRow: View {
  let entry: RecentLogEntry
  let now: Date

  @State private var isDetailExpanded = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: glyph)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        eyebrow
        Text(entry.summary)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
        if let details, !details.isEmpty {
          Text(details)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .lineLimit(isDetailExpanded ? nil : 2)
            .truncationMode(.middle)
            .fixedSize(horizontal: false, vertical: isDetailExpanded)
            .textSelection(.enabled)
        }
        if let relative = relativeTimestamp {
          Text(relative)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(.rect)
    .onTapGesture {
      guard details?.isEmpty == false else { return }
      withAnimation(.snappy(duration: 0.2)) { isDetailExpanded.toggle() }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("mobileDiagnostics.log.\(entry.id)")
  }

  private var details: String? { entry.details }

  /// Names where the row came from: the localized MetricKit kind when the
  /// system reported it, otherwise the raw `error_logs.source`
  /// (``RecentLogEntry/origin``, e.g. `ios.cloud_sync.cycle`).
  ///
  /// The raw source is deliberately not mapped to friendlier copy. A mapping
  /// table only covers the sources that existed when it was written, so a newly
  /// logging subsystem would show up unlabeled in the one panel whose job is to
  /// say what failed; the identifier is precise and needs no upkeep.
  @ViewBuilder
  private var eyebrow: some View {
    if let kindLabel {
      Text(kindLabel)
        .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        .textCase(.uppercase)
        .foregroundStyle(tint)
    } else if let origin = entry.origin, !origin.isEmpty {
      Text(origin)
        .font(LorvexDesign.Typography.tertiaryText.monospaced())
        .foregroundStyle(tint)
    }
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
    return LorvexDateFormatters.relative(date, to: now, unitsStyle: .abbreviated, dateTimeStyle: .numeric)
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
    if let kindLabel {
      label = "\(kindLabel): \(label)"
    } else if let origin = entry.origin, !origin.isEmpty {
      label = "\(origin): \(label)"
    }
    if let relative = relativeTimestamp { label += ", \(relative)" }
    return label
  }
}
