import LorvexCore
import SwiftUI

/// The edit and delete flows an event's detail panel starts, shared by every
/// surface that shows one (the Calendar workspace and Today). A surface keeps
/// one instance in `@State`, calls ``beginEditing(_:store:)`` and
/// ``requestDelete(_:)`` from the panel's buttons, and mounts
/// ``View/calendarEventActions(_:store:)`` once, which presents the shared
/// create/edit sheet and the delete confirmations.
///
/// Deleting a plain event asks once; deleting a repeating event asks which
/// occurrences to delete (this one, this and following, or all).
@MainActor
@Observable
final class CalendarEventActions {
  /// The create/edit sheet being presented, or nil.
  var activeSheet: CalendarEventSheet.Mode?
  /// The event awaiting a delete confirmation, or nil.
  var deletingEvent: CalendarTimelineEvent?
  /// True while ``deletingEvent`` repeats and its occurrence scope is asked.
  var isShowingDeleteScope = false

  /// Opens the create sheet on the store's staged draft.
  func beginCreating(store: AppStore) {
    store.beginCreateCalendarDraft()
    activeSheet = .create
  }

  /// Opens `event`'s edit form: selects it so its detail panel stays behind
  /// the sheet, stages its draft, then presents the sheet in edit mode. The
  /// event's calendar lives only in the EventKit mirror, so it is resolved
  /// live to preselect the form's calendar picker.
  func beginEditing(_ event: CalendarTimelineEvent, store: AppStore) {
    store.selectCalendarEvent(event)
    store.prepareCalendarDraft(for: event)
    activeSheet = .edit(event)
    Task { await store.resolveDraftTargetCalendar(for: event) }
  }

  /// Stages `event` for deletion. Only Lorvex-owned (editable) events delete.
  func requestDelete(_ event: CalendarTimelineEvent) {
    guard event.editable else { return }
    deletingEvent = event
    isShowingDeleteScope = event.supportsScopedMutation
  }

  fileprivate func runScopedDelete(_ scope: CalendarEventEditScope, store: AppStore) {
    guard let event = deletingEvent else { return }
    deletingEvent = nil
    isShowingDeleteScope = false
    Task { await store.deleteScopedCalendarEvent(event, scope: scope) }
  }
}

extension View {
  /// Presents `actions`' create/edit sheet and delete confirmations.
  func calendarEventActions(_ actions: CalendarEventActions, store: AppStore) -> some View {
    modifier(CalendarEventActionsHost(actions: actions, store: store))
  }
}

private struct CalendarEventActionsHost: ViewModifier {
  @Bindable var actions: CalendarEventActions
  @Bindable var store: AppStore

  func body(content: Content) -> some View {
    content
      .sheet(item: $actions.activeSheet, onDismiss: { store.restoreStashedCalendarDraft() }) { mode in
        CalendarEventSheet(store: store, mode: mode, dismiss: { actions.activeSheet = nil })
      }
      .confirmationDialog(
        actions.deletingEvent.map {
          String(
            format: String(
              localized: "calendar.delete_event.confirm.title",
              defaultValue: "Delete event \u{201C}%@\u{201D}?",
              table: "Localizable",
              bundle: LorvexL10n.bundle),
            $0.title)
        } ?? "",
        isPresented: Binding(
          get: { actions.deletingEvent != nil && !actions.isShowingDeleteScope },
          set: { if !$0 { actions.deletingEvent = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button(
          String(
            localized: "common.delete", defaultValue: "Delete", table: "Localizable",
            bundle: LorvexL10n.bundle), role: .destructive
        ) {
          if let event = actions.deletingEvent {
            actions.deletingEvent = nil
            Task { await store.deleteCalendarEvent(event) }
          }
        }
        Button(
          String(
            localized: "common.keep", defaultValue: "Keep", table: "Localizable",
            bundle: LorvexL10n.bundle), role: .cancel
        ) {
          actions.deletingEvent = nil
        }
      }
      .confirmationDialog(
        String(
          localized: "calendar.delete_event.scope.title",
          defaultValue: "Delete this repeating event?",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        isPresented: $actions.isShowingDeleteScope,
        titleVisibility: .visible
      ) {
        Button(
          String(
            localized: "calendar.recurring_scope.this_event", defaultValue: "This Event",
            table: "Localizable", bundle: LorvexL10n.bundle)
        ) {
          actions.runScopedDelete(.thisEvent, store: store)
        }
        Button(
          String(
            localized: "calendar.recurring_scope.this_and_following",
            defaultValue: "This and Following Events",
            table: "Localizable",
            bundle: LorvexL10n.bundle)
        ) {
          actions.runScopedDelete(.thisAndFollowing, store: store)
        }
        Button(
          String(
            localized: "calendar.recurring_scope.all_events", defaultValue: "All Events",
            table: "Localizable", bundle: LorvexL10n.bundle), role: .destructive
        ) {
          actions.runScopedDelete(.allEvents, store: store)
        }
        Button(
          String(
            localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
            bundle: LorvexL10n.bundle), role: .cancel
        ) {
          actions.isShowingDeleteScope = false
          actions.deletingEvent = nil
        }
      }
  }
}
