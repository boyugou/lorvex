import Foundation
import SwiftUI

/// How many tasks were finished on each of a review week's seven days, oldest
/// first, counted in the product's logical time zone.
public struct LorvexWeekShape: Equatable, Sendable {
  public struct Day: Equatable, Sendable, Identifiable {
    /// The logical day as `yyyy-MM-dd`.
    public let key: String
    public let finished: Int
    public var id: String { key }
  }

  public let days: [Day]

  /// The most finished on one day; 0 for a week with nothing finished.
  public var peak: Int { days.map(\.finished).max() ?? 0 }

  /// The seven days ending on `endKey`, each counting the `completedAt`
  /// timestamps (ISO 8601, with or without fractional seconds) that fall on
  /// it in `timeZone`. Timestamps outside the week or unreadable are ignored.
  public static func build(endKey: String, completedAt: [String], timeZone: TimeZone) -> LorvexWeekShape {
    let keys = (0..<7).reversed().compactMap { LorvexDateFormatters.ymdUTCAddingDays(endKey, days: -$0) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var counts: [String: Int] = [:]
    for stamp in completedAt {
      guard
        let instant = LorvexDateFormatters.iso8601Fractional.date(from: stamp)
          ?? LorvexDateFormatters.iso8601.date(from: stamp)
      else { continue }
      let parts = calendar.dateComponents([.year, .month, .day], from: instant)
      guard let year = parts.year, let month = parts.month, let day = parts.day else { continue }
      counts[String(format: "%04d-%02d-%02d", year, month, day), default: 0] += 1
    }
    return LorvexWeekShape(days: keys.map { Day(key: $0, finished: counts[$0] ?? 0) })
  }

  /// The week ending on `endKey` as `core` holds it. The completed tasks are
  /// read a day wider on each side, since the core compares completion
  /// timestamps by UTC day, then counted by logical day.
  public static func load(endingOn endKey: String, timeZone: TimeZone, from core: any LorvexCoreServicing)
    async throws -> LorvexWeekShape
  {
    guard let from = LorvexDateFormatters.ymdUTCAddingDays(endKey, days: -7),
      let to = LorvexDateFormatters.ymdUTCAddingDays(endKey, days: 1)
    else { return build(endKey: endKey, completedAt: [], timeZone: timeZone) }
    var query = TaskListQueryRequest(status: "completed")
    query.completedFrom = from
    query.completedTo = to
    query.limit = 500
    let page = try await core.listTasks(query: query)
    return build(endKey: endKey, completedAt: page.tasks.compactMap(\.completedAt), timeZone: timeZone)
  }
}

/// A review week's shape as seven short bars, one per day oldest first, each
/// as tall as the day's finished count against the week's busiest day, with
/// the count above a bar that has one and the day's narrow weekday under
/// every bar. A day with nothing finished keeps a faint stub, so the week
/// still reads as seven days. VoiceOver reads the strip as one sentence built
/// from ``Words``.
public struct LorvexWeekShapeStrip: View {
  public struct Words {
    /// "Finished each day".
    public var label: String
    /// "Monday, 2" from a full weekday name and that day's count.
    public var dayCount: (String, Int) -> String

    public init(label: String, dayCount: @escaping (String, Int) -> String) {
      self.label = label
      self.dayCount = dayCount
    }
  }

  private let shape: LorvexWeekShape
  private let words: Words

  @ScaledMetric(relativeTo: .footnote) private var barHeight: CGFloat = 36
  @ScaledMetric(relativeTo: .footnote) private var barWidth: CGFloat = 12
  @ScaledMetric(relativeTo: .footnote) private var columnWidth: CGFloat = 26

  public init(shape: LorvexWeekShape, words: Words) {
    self.shape = shape
    self.words = words
  }

  public var body: some View {
    HStack(alignment: .bottom, spacing: LorvexDesign.Spacing.xs) {
      ForEach(shape.days) { day in
        VStack(spacing: LorvexDesign.Spacing.xs) {
          Text(day.finished > 0 ? "\(day.finished)" : " ")
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .fixedSize()
          Capsule()
            .fill(day.finished > 0 ? AnyShapeStyle(LorvexDesign.Palette.done.opacity(0.8)) : AnyShapeStyle(.quaternary))
            .frame(width: barWidth, height: height(day.finished))
          Text(Self.weekday(day.key, style: .narrow))
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .fixedSize()
        }
        // The columns share the width they are given, up to the scaled column
        // width, so the strip fits a phone-width page at the accessibility
        // sizes instead of widening the page past the screen.
        .frame(minWidth: 0, maxWidth: columnWidth)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityIdentifier("review.week.shape")
  }

  private var accessibilityText: String {
    let days = shape.days.map { words.dayCount(Self.weekday($0.key, style: .wide), $0.finished) }
    return "\(words.label): \(days.formatted(.list(type: .and, width: .narrow)))"
  }

  private func height(_ finished: Int) -> CGFloat {
    guard finished > 0, shape.peak > 0 else { return 3 }
    return max(6, barHeight * CGFloat(finished) / CGFloat(shape.peak))
  }

  /// A day key's weekday in the current locale ("M" / "Monday", "一" / "星期一").
  private static func weekday(_ key: String, style: Date.FormatStyle.Symbol.Weekday) -> String {
    guard let date = LorvexDateFormatters.ymdUTC.date(from: key) else { return "" }
    var format = Date.FormatStyle().weekday(style)
    format.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return date.formatted(format)
  }
}
