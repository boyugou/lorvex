import LorvexCore
import SwiftUI
#if os(macOS)
  import AppKit
#endif

// MARK: - Shared metrics, hour cell, empty overlay, and overflow helpers

enum CalendarWeekGridMetrics {
  /// The timeline grid's hour-row height, from the design system's calendar
  /// metrics so the grid's vertical scale is one tokenized decision.
  static let hourHeight = LorvexDesign.CalendarMetrics.hourHeight
  /// The narrowest hour gutter, which fits English labels ("11 PM").
  static let gutterWidth: CGFloat = 50
  /// How much narrower than the gutter a label's frame is. The frame is centred
  /// in the gutter, so a label ends half of this short of the first day column.
  static let gutterLabelInset: CGFloat = 6

  /// The gutter's width for the hour `labels` and the all-day `allDayLabel`: wide
  /// enough for the widest hour label and for the widest word of the all-day
  /// label, each on one line. The all-day label wraps between its words, so a
  /// word is the least it can be narrowed to without breaking inside it.
  @MainActor static func gutterWidth(fittingHourLabels labels: [String], allDayLabel: String) -> CGFloat {
    gutterWidth(fitting: labels + allDayLabel.split(whereSeparator: \.isWhitespace).map(String.init))
  }

  /// The gutter's width for `labels`: the widest label on one line in the
  /// gutter's font, plus its inset, and never narrower than ``gutterWidth``.
  /// The 12-hour labels of Chinese and Korean ("上午10時", "오전 10시") are wider
  /// than English ones and would otherwise wrap onto a second line.
  @MainActor static func gutterWidth(fitting labels: [String]) -> CGFloat {
    let key = labels.joined(separator: "\u{1F}")
    if let cached = fittedGutterWidths[key] { return cached }
    let font = NSFont.preferredFont(forTextStyle: .subheadline)
    let widest = labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    let width = max(gutterWidth, (widest + gutterLabelInset + 2).rounded(.up))
    fittedGutterWidths[key] = width
    return width
  }

  @MainActor private static var fittedGutterWidths: [String: CGFloat] = [:]
  static let headerGutterHeight: CGFloat = 38
  static let headerVerticalPadding: CGFloat = 4
  static let dayNumberSize: CGFloat = 26
  static let allDayStripMinHeight: CGFloat = 20
  static let allDayStripContentPadding: CGFloat = 4
  static let allDayStripEmptyPadding: CGFloat = 1
  /// Maximum all-day pills (events + scheduled tasks) shown per day column
  /// before the rest collapse into a "+N more" overflow pill, so a day with many
  /// all-day items can't grow the strip without bound and shove the timed grid
  /// off-screen. When capped, the last slot is the overflow pill.
  static let allDayMaxItems = 3
  static let hourLineOpacity: CGFloat = 0.5
  static let halfHourLineOpacity: CGFloat = 0.18
  /// Corner radius for a timed event block and its drag-to-create preview ghost.
  /// Deliberately tighter than `LorvexDesign.Radius.s` (6): a block is often as
  /// short as the 16pt that `CalendarGridModel.minBlockMinutes` gives a short
  /// one, where a 6pt radius reads as an over-rounded pill rather than a
  /// calendar block.
  static let eventCornerRadius: CGFloat = 4
}

/// Content-only re-scroll key for the week grid: the visible week plus every
/// week and anchor hour only — block geometry is intentionally excluded so
/// that moving or resizing an event doesn't yank the scroll position back to
/// the anchor. Re-scroll fires only on week navigation.
func calendarWeekScrollAnchorSignature(
  columns: [CalendarGridDay],
  anchorHour: Int,
  weekStart: Date
) -> String {
  let weekKey = AppStore.ymdFormatter.string(from: weekStart)
  return [weekKey, "\(anchorHour)"].joined(separator: "|")
}

struct CalendarWeekGridHourCell: View {
  let hourHeight: CGFloat

  var body: some View {
    Rectangle()
      .fill(Color.clear)
      .frame(height: hourHeight)
      .overlay(alignment: .top) {
        Divider()
          .opacity(CalendarWeekGridMetrics.hourLineOpacity)
      }
      .overlay(alignment: .top) {
        Divider()
          .opacity(CalendarWeekGridMetrics.halfHourLineOpacity)
          .offset(y: hourHeight / 2)
      }
  }
}

/// Shown over an empty grid when Calendar access is denied, restricted, or
/// add-only — states an in-app prompt can't fix — so the grid reads as
/// "access is off," not "you have nothing scheduled." It only appears for
/// `needsSettingsRecovery`; a user who never connected a calendar
/// (`notDetermined`) sees the bare grid rather than being nagged.
struct CalendarWeekAuthorizeOverlay: View {
  @Environment(\.openURL) private var openURL

  private static let settingsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")

  var body: some View {
    HStack(alignment: .center, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "calendar.badge.exclamationmark")
        .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
        .foregroundStyle(LorvexDesign.Palette.warning)
        .frame(width: 20)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        Text(LocalizedStringResource("calendar.week.unauthorized.title", defaultValue: "Calendar Access Off", table: "Localizable", bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.primaryEmphasis)
          .lineLimit(1)

        Text(LocalizedStringResource(
          "calendar.week.unauthorized.description",
          defaultValue: "Turn on Calendar access in System Settings to see your events here.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ))
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button {
        if let url = Self.settingsURL { openURL(url) }
      } label: {
        Label {
          Text(LocalizedStringResource("calendar.week.unauthorized.open_settings", defaultValue: "Open Settings", table: "Localizable", bundle: LorvexL10n.bundle))
        } icon: {
          Image(systemName: "gearshape")
        }
      }
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.capsule)
      .controlSize(.small)
    }
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .padding(.vertical, LorvexDesign.Spacing.s)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    .overlay {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
        .stroke(.separator.opacity(0.12), lineWidth: 0.5)
    }
    .accessibilityIdentifier("calendar.week.unauthorized")
  }
}

// MARK: - Pointer cursors

#if os(macOS)
/// Applies a fixed AppKit cursor over its content via cursor rects. Unlike
/// `NSCursor.push()/pop()`, cursor rects compose predictably — the topmost rect
/// under the pointer wins — so an event block's pointing-hand cursor and its
/// resize handles' resize cursor coexist, and a block that scrolls away or
/// collapses mid-hover can't leak a pushed cursor onto the rest of the UI.
struct CalendarCursorView: NSViewRepresentable {
  let cursor: NSCursor

  final class CursorView: NSView {
    var cursor: NSCursor = .arrow
    override func resetCursorRects() {
      super.resetCursorRects()
      addCursorRect(bounds, cursor: cursor)
    }
  }

  func makeNSView(context: Context) -> CursorView {
    let view = CursorView(frame: .zero)
    view.cursor = cursor
    view.wantsLayer = false
    return view
  }

  func updateNSView(_ nsView: CursorView, context: Context) { nsView.cursor = cursor }
}
#endif

extension View {
  /// The pointing-hand cursor over a clickable calendar item (event block,
  /// all-day pill). A no-op off macOS.
  @ViewBuilder
  func calendarPointingHandCursor() -> some View {
    #if os(macOS)
      overlay(CalendarCursorView(cursor: .pointingHand).allowsHitTesting(false))
    #else
      self
    #endif
  }

  /// The vertical resize cursor over an event block's drag-to-resize handle.
  /// A no-op off macOS.
  @ViewBuilder
  func calendarResizeCursor() -> some View {
    #if os(macOS)
      overlay(CalendarCursorView(cursor: .resizeUpDown).allowsHitTesting(false))
    #else
      self
    #endif
  }
}
