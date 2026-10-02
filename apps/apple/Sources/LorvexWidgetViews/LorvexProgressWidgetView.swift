import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI
import WidgetKit

/// The day's progress through Today in the systemSmall, accessoryCircular, and
/// accessoryInline families: the tasks done today against those plus the
/// tasks still on Today's list.
///
/// Small draws a ring that fills toward the day's total, with the count done
/// and the total ("3/8") at its center, under the widget's title and over how
/// many tasks are left. The ring turns green with a check once nothing is
/// left; a day with nothing done and nothing on Today shows the bare track
/// around a sun. The ring sizes to the height between the title and that
/// line, so it fills the widget on every platform's widget size. The view
/// draws inside WidgetKit's content margins and adds none of its own.
public struct ProgressWidgetView: View {
  public let snapshot: WidgetSnapshot
  public let family: WidgetFamilyKind
  public let staleAgeLabel: String?

  public init(snapshot: WidgetSnapshot, family: WidgetFamilyKind, staleAgeLabel: String? = nil) {
    self.snapshot = snapshot
    self.family = family
    self.staleAgeLabel = staleAgeLabel
  }

  /// Today's progress: the tasks completed today over those plus the tasks
  /// still on Today's list. Completions count by the instant they happened,
  /// whatever the task's dates, so finishing anything today moves the ring;
  /// the list's length is uncapped (``WidgetSnapshot/Stats/todayCount``).
  /// Pure and static so the ratio is unit-testable without rendering the view.
  public nonisolated static func todayProgress(completedToday: Int, leftToday: Int)
    -> (completed: Int, total: Int, ratio: Double)
  {
    let completed = max(0, completedToday)
    let total = completed + max(0, leftToday)
    let ratio = total > 0 ? min(1, Double(completed) / Double(total)) : 0
    return (completed, total, ratio)
  }

  private var progress: (completed: Int, total: Int, ratio: Double) {
    Self.todayProgress(
      completedToday: snapshot.stats.completedTodayCount, leftToday: snapshot.stats.todayCount)
  }

  private var completedCount: Int { progress.completed }
  private var totalCount: Int { progress.total }
  private var ratio: Double { progress.ratio }
  private var leftCount: Int { totalCount - completedCount }
  private var isAllDone: Bool { totalCount > 0 && leftCount == 0 }

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
    .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    // Plural pivots on the task total; both numbers feed the format.
    String(
      localized: "widget.progress.a11y",
      defaultValue: "\(completedCount) of \(totalCount) tasks completed today",
      table: "Localizable", bundle: WidgetL10n.bundle)
  }

  private var smallView: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("widget.progress.title", bundle: WidgetL10n.bundle)
          .font(WidgetType.label)
          .foregroundStyle(LorvexDesign.Palette.accent)
          .lineLimit(1)
          .widgetAccentable()
        Spacer(minLength: 6)
        if let staleAgeLabel {
          WidgetStaleAgeLabel(staleAgeLabel)
        }
      }
      ring
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
      footer
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var tint: Color { isAllDone ? LorvexDesign.Palette.done : LorvexDesign.Palette.accent }

  /// The ring takes the square the height leaves it; its stroke stays the
  /// same weight at any size.
  private var ring: some View {
    ZStack {
      Circle()
        .stroke(.quaternary, lineWidth: 8)
      LorvexProgressArc(fraction: ratio, style: tint, lineWidth: 8)
      if isAllDone {
        Image(systemName: "checkmark")
          .font(.title2.weight(.bold))
          .foregroundStyle(tint)
      } else if totalCount == 0 {
        Image(systemName: "sun.max")
          .font(.title2)
          .foregroundStyle(.secondary)
      } else {
        // One Text, not two in an HStack: a right-to-left layout reverses an
        // HStack, which would show "8/3" for three of eight, while one run of
        // text keeps the fraction in number order in every script.
        let done = Text(completedCount, format: .number)
          .font(.system(.title2, design: .rounded).weight(.bold))
        let total = Text("/\(totalCount)")
          .font(.system(.subheadline, design: .rounded).weight(.semibold))
          .foregroundStyle(.secondary)
        Text("\(done)\(total)")
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .padding(.horizontal, 8)
      }
    }
    .padding(4)
    .aspectRatio(1, contentMode: .fit)
  }

  @ViewBuilder
  private var footer: some View {
    Group {
      if isAllDone {
        Text("widget.small.all_clear", bundle: WidgetL10n.bundle)
          .foregroundStyle(LorvexDesign.Palette.done)
      } else if totalCount == 0 {
        Text("widget.small.all_clear.subtitle", bundle: WidgetL10n.bundle)
          .foregroundStyle(.secondary)
      } else {
        Text(
          String(
            localized: "widget.remaining",
            defaultValue: "\(leftCount) remaining",
            table: "Localizable", bundle: WidgetL10n.bundle)
        )
        .foregroundStyle(.secondary)
      }
    }
    .font(WidgetType.meta)
    .lineLimit(1)
    .frame(maxWidth: .infinity, alignment: .center)
  }
}
