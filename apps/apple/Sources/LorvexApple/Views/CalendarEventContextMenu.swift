import LorvexCore
import SwiftUI

/// The right-click menu of a calendar event on the week and month grids. Every
/// event opens its details; only a Lorvex-owned (editable) event can also be
/// edited or deleted, since an imported EventKit event is a read-only overlay.
struct CalendarEventContextMenu: View {
  let event: CalendarTimelineEvent
  let select: (CalendarTimelineEvent) -> Void
  let edit: (CalendarTimelineEvent) -> Void
  let requestDelete: (CalendarTimelineEvent) -> Void

  var body: some View {
    Button {
      select(event)
    } label: {
      Label(
        String(
          localized: "calendar.event.open_details", defaultValue: "Open Details",
          table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "sidebar.right")
    }
    if event.editable {
      Button {
        edit(event)
      } label: {
        Label(
          String(
            localized: "common.edit", defaultValue: "Edit", table: "Localizable",
            bundle: LorvexL10n.bundle), systemImage: "pencil")
      }
      Button(role: .destructive) {
        requestDelete(event)
      } label: {
        Label(
          String(
            localized: "common.delete", defaultValue: "Delete", table: "Localizable",
            bundle: LorvexL10n.bundle), systemImage: "trash")
      }
    }
  }
}
