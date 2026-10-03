import SwiftUI

/// The title and time inside a timed block on a calendar grid, arranged by the
/// room the block actually has rather than by fixed height thresholds, so a
/// script with taller lines (Devanagari, Thai, Arabic), a larger text size, or
/// a narrow lane still fits. The first arrangement that fits the block is
/// drawn:
///
/// 1. the title on up to two lines, with the time on its own line under it;
/// 2. the title on one line, with the time under it;
/// 3. one line: the title with the time beside it when both fit whole,
///    otherwise the title alone;
/// 4. that line without the padding, centered in the block;
/// 5. the title alone, centered and scaled down as far as ``minimumScale``,
///    so a block shorter than one line of text still shows the title whole
///    instead of clipping its lower half.
///
/// The first three arrangements keep `verticalPadding` above and below the
/// text; the last two give the block every point it has, at the cost of the
/// breathing room. A time shows the range ("1:00 – 1:30 PM") where it fits
/// the width, otherwise the single time ("1:00 PM"). An arrangement that
/// leaves the time out relies on the block's accessibility label, which the
/// caller sets, to name it.
///
/// `accessory` leads every arrangement, aligned to the title's first baseline
/// (a task block's completion circle); an event block passes none. A done
/// block (a plan block whose task is completed) reads struck through and
/// secondary.
public struct LorvexCalendarBlockText<Accessory: View>: View {
  /// The smallest scale the fifth arrangement draws the title at. A block
  /// still shorter than the title's line at this size clips it evenly at the
  /// top and bottom, which keeps the middle of the glyphs readable.
  public static var minimumScale: CGFloat { 0.8 }

  private let title: String
  private let time: String?
  private let range: String?
  private let isDone: Bool
  private let verticalPadding: CGFloat
  private let accessorySpacing: CGFloat
  private let accessory: Accessory

  /// - Parameters:
  ///   - title: The event's or task's title.
  ///   - time: The block's time: its start ("1:00 PM"), or the end of an event
  ///     that started on an earlier day ("Until 1:00 AM"); nil for a block
  ///     that shows no time.
  ///   - range: The time range ("1:00 – 1:30 PM"), drawn instead of `time`
  ///     where it fits the width; nil to always draw `time`.
  ///   - isDone: Strikes the title through and draws it secondary.
  ///   - verticalPadding: The space above and below the text in every
  ///     arrangement but the last.
  ///   - accessorySpacing: The gap between `accessory` and the text.
  ///   - accessory: The view leading the text, aligned to its first baseline.
  public init(
    title: String,
    time: String?,
    range: String? = nil,
    isDone: Bool = false,
    verticalPadding: CGFloat = 2,
    accessorySpacing: CGFloat = 3,
    @ViewBuilder accessory: () -> Accessory
  ) {
    self.title = title
    self.time = time
    self.range = range
    self.isDone = isDone
    self.verticalPadding = verticalPadding
    self.accessorySpacing = accessorySpacing
    self.accessory = accessory()
  }

  public var body: some View {
    ViewThatFits(in: .vertical) {
      if let time {
        padded(stacked(titleLines: 2, time: time))
        padded(stacked(titleLines: 1, time: time))
      } else {
        padded(titleText.lineLimit(2))
      }
      padded(oneLine)
      centered(oneLine)
      centered(titleText.lineLimit(1).minimumScaleFactor(Self.minimumScale))
    }
  }

  /// The accessory beside `text`, padded above and below.
  private func padded(_ text: some View) -> some View {
    beside(text).padding(.vertical, verticalPadding)
  }

  /// The accessory beside `text`, centered in the block's full height. The
  /// zero minimum lets a line taller than the block overflow it evenly at the
  /// top and bottom instead of making the block's content taller than the
  /// block.
  private func centered(_ text: some View) -> some View {
    beside(text).frame(minHeight: 0, maxHeight: .infinity)
  }

  private func beside(_ text: some View) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: accessorySpacing) {
      accessory
      text
    }
  }

  /// The title with the time beside it when both fit whole (the range, else
  /// the single time), otherwise the title alone.
  private var oneLine: some View {
    ViewThatFits(in: .horizontal) {
      if let time {
        if let range { titleBeside(range) }
        titleBeside(time)
      }
      titleText.lineLimit(1)
    }
  }

  private func titleBeside(_ label: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.xs) {
      titleText.lineLimit(1)
      timeText(label)
    }
  }

  /// The title over its time line.
  private func stacked(titleLines: Int, time: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      titleText.lineLimit(titleLines)
      ViewThatFits(in: .horizontal) {
        if let range { timeText(range) }
        timeText(time)
      }
    }
  }

  private var titleText: some View {
    Text(userContent: title)
      .font(LorvexDesign.Typography.tertiaryText.weight(Self.titleWeight))
      .foregroundStyle(isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
      .strikethrough(isDone)
  }

  /// Whole on one line, so a `ViewThatFits` can tell whether it fits.
  private func timeText(_ label: String) -> some View {
    Text(label)
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)
      .monospacedDigit()
      .lineLimit(1)
      .fixedSize()
  }

  /// The Mac's blocks are smaller and denser than the phone's, so their
  /// titles take a heavier weight to stay legible.
  private static var titleWeight: Font.Weight {
    #if os(macOS)
      .semibold
    #else
      .medium
    #endif
  }
}

extension LorvexCalendarBlockText where Accessory == EmptyView {
  /// A block with no leading accessory, such as a calendar event's.
  public init(
    title: String,
    time: String?,
    range: String? = nil,
    isDone: Bool = false,
    verticalPadding: CGFloat = 2
  ) {
    self.init(
      title: title, time: time, range: range, isDone: isDone, verticalPadding: verticalPadding
    ) { EmptyView() }
  }
}
