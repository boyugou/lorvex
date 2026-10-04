import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

extension LorvexDesign {
  /// The Lorvex color system. Every color a view uses is named by what it
  /// means, and each hue carries at most one meaning per surface family (see
  /// `docs/design/DESIGN_SYSTEM.md`): red is overdue / P1 / error / destructive,
  /// orange is due-soon / P2 / warning, green is done / success, the platform
  /// accent is selection / started work / primary action, and the secondary gray is
  /// every neutral (counts, cancelled, someday, blocked, low priority). Colors
  /// are system-semantic so light and dark both render correctly; views never
  /// name a raw hue (`script/verify_design_tokens.py` enforces this).
  public enum Palette {
    // MARK: Accent

    /// The platform accent: selection, started work, primary actions, links.
    /// Aliases `Color.accentColor` so call sites read semantically; there is no
    /// second brand blue. watchOS has no accent of its own without an asset
    /// catalog (`Color.accentColor` renders as a light grey there, the same as
    /// disabled text), so the watch reads the system blue that iOS shows by
    /// default.
    #if os(watchOS)
      public static let accent: Color = .blue
    #else
      public static let accent: Color = .accentColor
    #endif

    // MARK: Task time-state

    /// Past due — demands attention.
    public static let overdue: Color = .red
    /// Due today or soon — gentle urgency.
    public static let dueSoon: Color = .orange
    /// Someday / parked — deliberately quiet.
    public static let someday: Color = .secondary
    /// Completed.
    public static let done: Color = .green
    /// Cancelled — history, not an alarm.
    public static let cancelled: Color = .secondary
    /// Waiting on an open dependency.
    public static let blocked: Color = .secondary

    // MARK: Priority

    /// P1 — urgent.
    public static let priorityHigh: Color = .red
    /// P2 — elevated.
    public static let priorityMedium: Color = .orange
    /// P3 — recedes.
    public static let priorityLow: Color = .secondary

    // MARK: Severity — system state in Settings, diagnostics, editors, banners.

    public static let neutral: Color = .secondary
    public static let success: Color = .green
    public static let warning: Color = .orange
    public static let error: Color = .red
    /// Destructive actions (delete, erase, cancel a task).
    public static let destructive: Color = .red

    // MARK: Reflection

    /// Mood in daily and weekly reviews.
    public static let mood: Color = .pink
    /// Energy in daily and weekly reviews.
    public static let energy: Color = .yellow

    // MARK: Calendar

    /// The current-time line in the calendar grids (the platform convention).
    public static let nowIndicator: Color = .red

    // MARK: Identity — the only non-semantic colors: entity tiles and blocks.

    /// Fallback hues for habits without a user-chosen color, chosen by id hash.
    /// Green is excluded so an unfinished habit never reads as done.
    public static let identityHues: [Color] = [
      .blue, .teal, .cyan, .orange, .pink, .purple, .indigo, .brown,
    ]

    /// Fixed tints for destinations and smart lists, used on their icon tiles
    /// (the convention Reminders and Settings follow), never on status text.
    public enum Destination {
      public static let today: Color = .accentColor
      public static let tasks: Color = .blue
      public static let calendar: Color = .red
      public static let habits: Color = .green
      public static let lists: Color = .orange
      public static let memory: Color = .purple
      public static let review: Color = .indigo
      public static let settings: Color = .gray
      public static let all: Color = .gray
      public static let scheduled: Color = .red
      public static let priority: Color = .orange
      public static let someday: Color = .indigo
    }

    // MARK: Time of day

    /// The wash at the top of Today, tinted like the sky at that hour: cool in
    /// the morning, warm through the day, peach in the evening. Decorative only;
    /// it never carries status, so it sits outside the semantic hue table.
    public enum Sky {
      public static let morning: Color = Color(red: 0.56, green: 0.71, blue: 1.0)
      public static let day: Color = Color(red: 1.0, green: 0.76, blue: 0.48)
      public static let evening: Color = Color(red: 1.0, green: 0.60, blue: 0.42)
      /// The sun on the day arc: the one warm mark on an empty day.
      public static let sun: Color = .orange
    }

    // MARK: Surfaces

    /// The base grouped background a screen sits on.
    public static let groupedBackground: Color = {
      #if canImport(UIKit) && !os(watchOS)
        return Color(uiColor: .systemGroupedBackground)
      #elseif canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
      #else
        return Color.clear
      #endif
    }()

    /// The elevated surface cards sit on, one step above `groupedBackground`.
    public static let card: Color = {
      #if canImport(UIKit) && !os(watchOS)
        return Color(uiColor: .secondarySystemGroupedBackground)
      #elseif canImport(AppKit)
        return Color(nsColor: .controlBackgroundColor)
      #else
        return Color.gray.opacity(0.12)
      #endif
    }()

    /// A nested group inside a card or a workspace column.
    public static let insetFill: Color = Color.secondary.opacity(0.08)
    /// Pointer hover on rows and controls (macOS).
    public static let hoverFill: Color = Color.secondary.opacity(0.12)
    /// The selected row or item.
    public static let selectionFill: Color = Color.accentColor.opacity(0.15)
    /// The selection behind a sidebar row drawn outside the source list, such
    /// as the pinned footer: the fill the list itself shows for a selection
    /// while it does not hold keyboard focus, so the two read as one control.
    public static let sidebarSelectionFill: Color = {
      #if canImport(AppKit) && !canImport(UIKit)
        return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
      #else
        return Color.secondary.opacity(0.16)
      #endif
    }()

    /// Alpha for the empty part of a tinted progress control drawn in its own
    /// hue on a card: a ring's track, a milestone bar's rail. A hue at one
    /// fixed alpha reads as a pastel over a light card and all but vanishes
    /// over a dark one, so the alpha follows the color scheme; callers read
    /// `@Environment(\.colorScheme)` and pass it here.
    public static func trackOpacity(for colorScheme: ColorScheme) -> Double {
      colorScheme == .dark ? 0.36 : 0.18
    }

    /// Opacity for the marks of something the clock has cleared: a past day's
    /// load strip, a finished meeting's color bar, the circle of a task done
    /// earlier in the day. Only marks fade. Text on a past item keeps at least
    /// the secondary style, because secondary text at this opacity measures
    /// under 2:1 and reads as disabled.
    public static let pastMarkOpacity: Double = 0.45

    /// The color of a text field's placeholder: the platform's own placeholder
    /// color, so a placeholder drawn by hand over an editor (the notes editors')
    /// matches the one in the system field beside it, including the darker value
    /// the system gives it under Increase Contrast, which the hierarchical
    /// `.tertiary` style does not follow.
    public static let placeholderText: Color = {
      #if canImport(UIKit) && !os(watchOS)
        return Color(uiColor: .placeholderText)
      #elseif canImport(AppKit)
        return Color(nsColor: .placeholderTextColor)
      #else
        return Color.secondary
      #endif
    }()

    /// Hairline separators inside cards and between rows.
    public static let separator: Color = {
      #if canImport(UIKit) && !os(watchOS)
        return Color(uiColor: .separator)
      #elseif canImport(AppKit)
        return Color(nsColor: .separatorColor)
      #else
        return Color.secondary.opacity(0.3)
      #endif
    }()
  }
}

extension LorvexDesign.Radius {
  /// Card / grouped-container radius, matching each platform's grouped
  /// surfaces: 12 on macOS; 26 on iOS and iPadOS, the corner of an
  /// inset-grouped list section, so a card drawn beside the list's own
  /// sections has the same corners; 16 on watchOS.
  public static let card: CGFloat = {
    #if os(macOS)
      return 12
    #elseif os(iOS)
      return 26
    #else
      return 16
    #endif
  }()
}

extension LorvexDesign.Spacing {
  /// Standard inset for card content and screen gutters.
  public static let cardPadding: CGFloat = 16
}
