import LorvexCore
import SwiftUI

private struct MobileCalendarDeleteScopeDialogModifier: ViewModifier {
  @Binding var event: CalendarTimelineEvent?
  let delete: (CalendarTimelineEvent, CalendarEventEditScope) async -> Bool

  func body(content: Content) -> some View {
    content.confirmationDialog(
      String(
        localized: "calendar.delete_event.scope.title",
        defaultValue: "Delete this repeating event?", table: "Localizable",
        bundle: MobileL10n.bundle),
      isPresented: Binding(
        get: { event != nil },
        set: { if !$0 { event = nil } }
      ),
      titleVisibility: .visible
    ) {
      scopeButton(
        String(
          localized: "calendar.recurring_scope.this_event", defaultValue: "This Event",
          table: "Localizable", bundle: MobileL10n.bundle),
        scope: .thisEvent,
        accessibilityIdentifier: "mobileCalendar.deleteScope.thisEvent")
      scopeButton(
        String(
          localized: "calendar.recurring_scope.this_and_following",
          defaultValue: "This and Following Events", table: "Localizable",
          bundle: MobileL10n.bundle),
        scope: .thisAndFollowing,
        accessibilityIdentifier: "mobileCalendar.deleteScope.thisAndFollowing")
      scopeButton(
        String(
          localized: "calendar.recurring_scope.delete_all_events",
          defaultValue: "Delete All Events", table: "Localizable", bundle: MobileL10n.bundle),
        scope: .allEvents,
        role: .destructive,
        accessibilityIdentifier: "mobileCalendar.deleteScope.allEvents")
      Button(
        String(
          localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
          bundle: MobileL10n.bundle),
        role: .cancel
      ) {}
    } message: {
      Text(
        String(
          localized: "calendar.delete_event.scope.message",
          defaultValue: "Choose which occurrences to delete.", table: "Localizable",
          bundle: MobileL10n.bundle))
    }
  }

  private func scopeButton(
    _ title: String,
    scope: CalendarEventEditScope,
    role: ButtonRole? = nil,
    accessibilityIdentifier: String
  ) -> some View {
    Button(title, role: role) {
      guard let selected = event else { return }
      event = nil
      Task { _ = await delete(selected, scope) }
    }
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}

extension View {
  func mobileCalendarDeleteScopeDialog(
    event: Binding<CalendarTimelineEvent?>,
    delete: @escaping (CalendarTimelineEvent, CalendarEventEditScope) async -> Bool
  ) -> some View {
    modifier(MobileCalendarDeleteScopeDialogModifier(event: event, delete: delete))
  }
}
