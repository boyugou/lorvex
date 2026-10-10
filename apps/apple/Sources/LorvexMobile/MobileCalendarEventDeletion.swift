import LorvexCore
import SwiftUI

/// How a calendar surface deletes the events it lists, and the question it
/// asks first. Every row, pill, and block of one surface shares `pending`, so
/// one question shows at a time, and each carries
/// ``SwiftUI/View/mobileCalendarEventDeletion(of:on:_:)`` so the question opens
/// at the control that raised it.
struct MobileCalendarEventDeletion {
  /// A deletion question: the event, and the one drawing of it that raised
  /// the question. A multi-day event is drawn once per day, and the day grid
  /// keeps pages beside the visible one that draw some of the same days, so
  /// the event alone would open the question at every drawing at once.
  struct Request: Identifiable, Equatable, Sendable {
    let event: CalendarTimelineEvent
    /// The surface that draws the event: the page of a pager, or `""` for a
    /// surface drawn once.
    let scope: String
    /// The day, as `yyyy-MM-dd`, the drawing stands under.
    let dayKey: String

    var id: String { "\(scope)/\(dayKey)/\(event.id)" }
  }

  /// The question being asked; `nil` while no question is open.
  let pending: Binding<Request?>
  /// Deletes an event that does not repeat.
  let deleteEvent: (CalendarTimelineEvent) async -> Bool
  /// Deletes the occurrences of a repeating event that `scope` names.
  let deleteScoped: (CalendarTimelineEvent, CalendarEventEditScope) async -> Bool
  /// The surface the drawings belong to (``Request/scope``).
  var scope = ""

  /// This deletion for the drawings of the surface `scope` names.
  func scoped(to scope: String) -> MobileCalendarEventDeletion {
    var scoped = self
    scoped.scope = scope
    return scoped
  }

  /// Opens the question for `event` as drawn under `dayKey`: a confirmation,
  /// or for a repeating event the choice of which occurrences to delete.
  func request(_ event: CalendarTimelineEvent, on dayKey: String) {
    pending.wrappedValue = Request(event: event, scope: scope, dayKey: dayKey)
  }

  /// A deletion that never asks and deletes nothing, for a surface drawn
  /// without a store.
  static var inert: MobileCalendarEventDeletion {
    MobileCalendarEventDeletion(
      pending: .constant(nil), deleteEvent: { _ in false }, deleteScoped: { _, _ in false })
  }
}

extension View {
  /// Asks before deleting `event`, as drawn under `dayKey`, once `deletion`
  /// holds that request as pending: a confirmation for an event that does not
  /// repeat, the choice of occurrences for one that does (This Event, This and
  /// Following Events, Delete All Events).
  ///
  /// On the iPhone a dialog is a popover whose arrow points at the view that
  /// carries the modifier, so attach this to the row, pill, or block the
  /// request comes from; it stays on screen while a context menu closes.
  /// A `destructive`-role swipe button would collapse the row and take the
  /// dialog with it, so a swipe that raises this question carries no role.
  ///
  /// The dialog reads `deletion.pending` when this view is evaluated again. A
  /// surface that skips re-evaluating its content, as the pager's pages do
  /// (``MobileCalendarDayPage``), has to count the open question among the
  /// inputs it compares.
  func mobileCalendarEventDeletion(
    of event: CalendarTimelineEvent, on dayKey: String, _ deletion: MobileCalendarEventDeletion
  ) -> some View {
    modifier(
      MobileCalendarEventDeletionModifier(
        request: .init(event: event, scope: deletion.scope, dayKey: dayKey), deletion: deletion))
  }
}

private struct MobileCalendarEventDeletionModifier: ViewModifier {
  let request: MobileCalendarEventDeletion.Request
  let deletion: MobileCalendarEventDeletion

  func body(content: Content) -> some View {
    if request.event.supportsScopedMutation {
      content.confirmationDialog(
        Self.scopeTitle,
        isPresented: deletion.pending.isHolding(request),
        titleVisibility: .visible
      ) {
        scopeButton(Self.thisEventTitle, scope: .thisEvent, identifier: "thisEvent")
        scopeButton(
          Self.thisAndFollowingTitle, scope: .thisAndFollowing, identifier: "thisAndFollowing")
        scopeButton(
          Self.allEventsTitle, scope: .allEvents, role: .destructive, identifier: "allEvents")
        Button(Self.cancelTitle, role: .cancel) {}
      } message: {
        Text(Self.scopeMessage)
      }
    } else {
      content.mobileDeleteConfirmation(
        of: request, pending: deletion.pending,
        title: String(
          format: String(
            localized: "calendar.delete_event.confirm.title",
            defaultValue: "Delete event \u{201C}%@\u{201D}?", table: "Localizable",
            bundle: MobileL10n.bundle),
          request.event.title)
      ) { request in
        Task { _ = await deletion.deleteEvent(request.event) }
      }
    }
  }

  private func scopeButton(
    _ title: String, scope: CalendarEventEditScope, role: ButtonRole? = nil, identifier: String
  ) -> some View {
    Button(title, role: role) {
      deletion.pending.wrappedValue = nil
      Task { _ = await deletion.deleteScoped(request.event, scope) }
    }
    .accessibilityIdentifier("mobileCalendar.deleteScope.\(identifier)")
  }

  private static var scopeTitle: String {
    String(
      localized: "calendar.delete_event.scope.title",
      defaultValue: "Delete this repeating event?", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  private static var scopeMessage: String {
    String(
      localized: "calendar.delete_event.scope.message",
      defaultValue: "Choose which occurrences to delete.", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  private static var thisEventTitle: String {
    String(
      localized: "calendar.recurring_scope.this_event", defaultValue: "This Event",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  private static var thisAndFollowingTitle: String {
    String(
      localized: "calendar.recurring_scope.this_and_following",
      defaultValue: "This and Following Events", table: "Localizable", bundle: MobileL10n.bundle)
  }

  private static var allEventsTitle: String {
    String(
      localized: "calendar.recurring_scope.delete_all_events",
      defaultValue: "Delete All Events", table: "Localizable", bundle: MobileL10n.bundle)
  }

  private static var cancelTitle: String {
    String(
      localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
      bundle: MobileL10n.bundle)
  }
}
