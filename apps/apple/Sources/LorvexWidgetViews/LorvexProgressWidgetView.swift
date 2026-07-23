import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI
import WidgetKit

/// Renders the daily progress gauge view in systemSmall, accessoryCircular, and accessoryInline families.
public struct ProgressWidgetView: View {
  public let snapshot: WidgetSnapshot
  public let family: WidgetFamilyKind
  public let staleAgeLabel: String?

  public init(snapshot: WidgetSnapshot, family: WidgetFamilyKind, staleAgeLabel: String? = nil) {
    self.snapshot = snapshot
    self.family = family
    self.staleAgeLabel = staleAgeLabel
  }

  /// Today's completion math: completed-today over completed-today plus
  /// still-open due today.
  ///
  /// Both terms are restricted to *due today*. Overdue is excluded on purpose:
  /// pairing an overdue-inclusive denominator (the old `todayTasks.count`) with a
  /// due-today-only numerator made the gauge inconsistent — completing an overdue
  /// task shrank the denominator without raising the numerator, and the gauge
  /// could never reach 100% while any overdue task remained. Overdue work is
  /// surfaced separately via the overdue count. Pure + static so the ratio is
  /// unit-testable without rendering the view.
  public nonisolated static func todayProgress(completedDueToday: Int, openDueToday: Int)
    -> (completed: Int, total: Int, ratio: Double)
  {
    let completed = max(0, completedDueToday)
    let total = completed + max(0, openDueToday)
    let ratio = total > 0 ? min(1, Double(completed) / Double(total)) : 0
    return (completed, total, ratio)
  }

  private var progress: (completed: Int, total: Int, ratio: Double) {
    Self.todayProgress(
      completedDueToday: snapshot.stats.completedTodayCount,
      openDueToday: snapshot.stats.dueTodayCount)
  }

  private var completedCount: Int { progress.completed }
  private var totalCount: Int { progress.total }
  private var ratio: Double { progress.ratio }

  public var body: some View {
    switch family {
    case .accessoryInline:
      inlineView
    case .accessoryCircular:
      circularView
    default:
      smallView
    }
  }

  private var inlineView: some View {
    Text(String(
      localized: "widget.progress.inline",
      defaultValue: "\(completedCount)/\(totalCount) tasks",
      table: "Localizable",
      bundle: WidgetL10n.bundle))
      .lineLimit(1)
  }

  private var circularView: some View {
    Gauge(value: ratio) {
      EmptyView()
    } currentValueLabel: {
      Text("\(completedCount)")
        .font(.system(.body, design: .rounded).weight(.bold))
    }
    .gaugeStyle(.accessoryCircular)
    .tint(LorvexDesign.Palette.done)
    .widgetAccentable()
    // Plural pivots on the task total; both numbers feed the format.
    .accessibilityLabel(
      String(
        localized: "widget.progress.a11y",
        defaultValue: "\(completedCount) of \(totalCount) tasks completed today",
        table: "Localizable", bundle: WidgetL10n.bundle))
  }

  private var metrics: LorvexWidgetViewMetrics { .metrics(for: .systemSmall) }

  private var smallView: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Image(systemName: "checkmark.circle.fill")
          .font(.headline)
          .foregroundStyle(LorvexDesign.Palette.done)
          .accessibilityHidden(true)
        Text("widget.progress.title", bundle: WidgetL10n.bundle)
          .font(.headline)
          .lineLimit(1)
        Spacer(minLength: 0)
      }

      Gauge(value: ratio) {
        EmptyView()
      } currentValueLabel: {
        VStack(spacing: 2) {
          Text("\(completedCount)")
            .font(.system(.title2, design: .rounded).weight(.bold))
          Text("widget.progress.done", bundle: WidgetL10n.bundle)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .gaugeStyle(.linearCapacity)
      .tint(LorvexDesign.Palette.done)
      .frame(maxWidth: .infinity)

      Spacer(minLength: 0)

      HStack(spacing: 8) {
        Text(
          String(
            localized: "widget.remaining",
            defaultValue: "\(totalCount - completedCount) remaining",
            table: "Localizable", bundle: WidgetL10n.bundle))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer(minLength: 6)
        if let staleAgeLabel {
          WidgetStaleAgeLabel(staleAgeLabel)
        }
      }
    }
    .padding(.horizontal, metrics.horizontalPadding)
    .padding(.vertical, metrics.verticalPadding)
  }
}
