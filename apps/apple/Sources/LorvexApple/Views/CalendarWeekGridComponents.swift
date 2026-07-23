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
  static let gutterWidth: CGFloat = 50
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
  /// Deliberately tighter than `LorvexDesign.Radius.s` (6): a block can render as
  /// short as `CalendarEventBlockMetrics.minimumHeight` (16pt), where a 6pt
  /// radius reads as an over-rounded pill rather than a calendar block.
  static let eventCornerRadius: CGFloat = 4
}

func calendarWeekOverflowTimeText(for event: CalendarTimelineEvent) -> String {
  lorvexClockTimeRange(start: event.startTime, end: event.endTime)
}

func calendarWeekOverflowBlockAccessibilityLabel(_ block: CalendarGridTimedBlock) -> String {
  calendarEventAccessibilityLabel(
    title: block.event.title,
    allDay: false,
    startTime: block.event.startTime.map(lorvexClockTimeLabel),
    endTime: block.event.endTime.map(lorvexClockTimeLabel),
    location: block.event.location,
    source: block.event.source
  )
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

struct CalendarWeekEmptyOverlay: View {
  let visibleDayCount: Int
  let createEvent: () -> Void

  private var isSingleDay: Bool { visibleDayCount == 1 }

  var body: some View {
    HStack(alignment: .center, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "calendar.badge.plus")
        .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
        .foregroundStyle(.tint)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .lineLimit(1)

        Text(description)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button {
        createEvent()
      } label: {
        Label {
          Text(String(localized: "calendar.create_event", defaultValue: "Create Event", table: "Localizable", bundle: LorvexL10n.bundle))
        } icon: {
          Image(systemName: "plus")
        }
      }
      .buttonStyle(.lorvexPrimary)
      .buttonBorderShape(.capsule)
      .controlSize(.small)
    }
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .padding(.vertical, LorvexDesign.Spacing.s)
    // Span the column band as a top banner rather than a fixed-width island
    // floating over the middle of the week — the empty state is about the whole
    // visible range, so it reads better anchored across it.
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    .overlay {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
        .stroke(.separator.opacity(0.12), lineWidth: 0.5)
    }
    .accessibilityIdentifier(isSingleDay ? "calendar.day.empty" : "calendar.week.empty")
  }

  private var title: LocalizedStringResource {
    if isSingleDay {
      return LocalizedStringResource("calendar.day.empty.title", defaultValue: "Open Day", table: "Localizable", bundle: LorvexL10n.bundle)
    }
    return LocalizedStringResource("calendar.week.empty.title", defaultValue: "Open Week", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private var description: LocalizedStringResource {
    if isSingleDay {
      return LocalizedStringResource(
        "calendar.day.empty.description",
        defaultValue: "No events or planned tasks are scheduled today.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
    return LocalizedStringResource(
      "calendar.week.empty.description",
      defaultValue: "No events or planned tasks are scheduled in this week.",
      table: "Localizable",
      bundle: LorvexL10n.bundle
    )
  }
}

/// Shown in place of the empty-week banner when Calendar access is denied,
/// restricted, or add-only — states an in-app prompt can't fix — so an empty
/// grid reads as "access is off," not "you have nothing scheduled." It only
/// appears for `needsSettingsRecovery`; a user who never connected a calendar
/// (`notDetermined`) keeps the normal empty state rather than being nagged.
struct CalendarWeekAuthorizeOverlay: View {
  @Environment(\.openURL) private var openURL

  private static let settingsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")

  var body: some View {
    HStack(alignment: .center, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "calendar.badge.exclamationmark")
        .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
        .foregroundStyle(.orange)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 2) {
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
      .buttonStyle(.lorvexPrimary)
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
