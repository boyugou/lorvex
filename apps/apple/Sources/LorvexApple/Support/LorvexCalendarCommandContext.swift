import LorvexCore
import SwiftUI

/// What the View menu's Calendar commands act on: the presentation state of the
/// Calendar workspace that is on screen in the key window. The workspace
/// publishes it as a focused scene value, so each command drives the same state
/// as the matching toolbar control. The value is `nil` whenever no window shows
/// the Calendar, and the commands are then absent from the menu.
struct LorvexCalendarCommandContext {
  /// The Day/Week/Month presentation, the workspace's persisted setting.
  let mode: Binding<CalendarPresentationMode>
  /// Whether the Unplanned Tasks rail stands beside the grid.
  let showsPlanRail: Binding<Bool>
  /// Whether the visible period already holds today, which leaves nothing to
  /// jump back to.
  let isViewingCurrent: Bool
  /// Moves the calendar to the period that holds today.
  let jumpToCurrent: () -> Void
}

private struct LorvexCalendarCommandContextKey: FocusedValueKey {
  typealias Value = LorvexCalendarCommandContext
}

extension FocusedValues {
  var lorvexCalendarCommandContext: LorvexCalendarCommandContext? {
    get { self[LorvexCalendarCommandContextKey.self] }
    set { self[LorvexCalendarCommandContextKey.self] = newValue }
  }
}

/// The Calendar's commands in the View menu: the jump back to today (⌘T), the
/// Day/Week/Month choice, and the Unplanned Tasks rail (⌥⌘U). They appear only
/// while a window shows the Calendar, so the View menu stays short on every
/// other workspace. The rail item is titled like Show Sidebar and Hide Sidebar,
/// by what choosing it does.
struct CalendarViewCommands: View {
  @FocusedValue(\.lorvexCalendarCommandContext) private var context

  var body: some View {
    if let context {
      Divider()

      Button(context.mode.wrappedValue.currentPeriodTitle, action: context.jumpToCurrent)
        .keyboardShortcut("t", modifiers: [.command])
        .disabled(context.isViewingCurrent)

      Picker(selection: context.mode) {
        ForEach(CalendarPresentationMode.allCases, id: \.self) { option in
          Text(option.title)
        }
      } label: {
        Text(CalendarPresentationMode.pickerLabel)
      }
      .pickerStyle(.inline)
      .labelsHidden()

      Button(Self.planRailTitle(isShown: context.showsPlanRail.wrappedValue)) {
        context.showsPlanRail.wrappedValue.toggle()
      }
      .keyboardShortcut("u", modifiers: [.command, .option])
    }
  }

  /// "Hide Unplanned Tasks" while the rail is shown, "Show Unplanned Tasks"
  /// otherwise.
  static func planRailTitle(isShown: Bool) -> String {
    if isShown {
      String(
        localized: "calendar.commands.hide_plan_rail", defaultValue: "Hide Unplanned Tasks",
        table: "Localizable", bundle: LorvexL10n.bundle)
    } else {
      String(
        localized: "calendar.commands.show_plan_rail", defaultValue: "Show Unplanned Tasks",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}
