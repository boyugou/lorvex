import SwiftUI

/// The text of an event's pill in a calendar grid's all-day strip: the title,
/// followed by a time in the secondary color, which a timed event of a day or
/// more shows on the day it starts (its start, "7:00 PM") and on the day it
/// ends ("Until 9:00 AM"). The first arrangement that fits the pill's width is
/// drawn:
///
/// 1. the title and the time, both whole;
/// 2. the title truncated to the room the whole time leaves it, while that
///    room is at least ``minimumTitleWidth`` (scaled with the text size);
/// 3. the title alone, truncated, since a pill that cannot name its event
///    says less than one without its time.
///
/// Every arrangement is one line. The caller sets the font, and sets the
/// pill's accessibility label to name the time, which the last arrangement
/// leaves out.
public struct LorvexCalendarStripLabel: View {
  /// The narrowest the title gets beside the time at the default text size:
  /// about five Latin letters and an ellipsis in the strip's text.
  public static let minimumTitleWidth: CGFloat = 40

  private let title: String
  private let time: String?
  @ScaledMetric(relativeTo: .footnote) private var titleRoom = LorvexCalendarStripLabel.minimumTitleWidth

  /// - Parameters:
  ///   - title: The event's title.
  ///   - time: The time the pill shows on its day, or nil for none.
  public init(title: String, time: String?) {
    self.title = title
    self.time = time
  }

  public var body: some View {
    ViewThatFits(in: .horizontal) {
      if let time {
        HStack(spacing: LorvexDesign.Spacing.xs) {
          titleText
          timeText(time)
        }
        // The title's ideal width is the minimum, so this arrangement fits
        // while the time leaves the title that much; drawn, the title takes
        // all the room left, up to its whole width.
        HStack(spacing: LorvexDesign.Spacing.xs) {
          titleText.frame(minWidth: titleRoom, idealWidth: titleRoom, alignment: .leading)
          timeText(time)
        }
      }
      titleText
    }
  }

  private var titleText: some View {
    Text(title).lineLimit(1)
  }

  private func timeText(_ time: String) -> some View {
    Text(time)
      .foregroundStyle(.secondary)
      .monospacedDigit()
      .lineLimit(1)
      .fixedSize()
  }
}
