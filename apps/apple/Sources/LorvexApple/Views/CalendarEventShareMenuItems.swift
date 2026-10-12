import LorvexCore
import SwiftUI

/// The Copy as Text and Share items of a calendar event's menus: the context
/// menu on the grids, in search results, and on Today's schedule, and the
/// inspector's overflow menu. Both carry the text ``CalendarEventShare`` builds,
/// the way a task's menus carry its text.
struct CalendarEventShareMenuItems: View {
  let event: CalendarTimelineEvent

  var body: some View {
    Button {
      CalendarEventShare.copy(event)
    } label: {
      Label(
        String(
          localized: "task.action.copy_as_text", defaultValue: "Copy as Text",
          table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "doc.on.doc")
    }
    .accessibilityIdentifier("calendar.event.copyAsText")
    ShareLink(item: CalendarEventShare.text(for: event)) {
      Label(
        String(
          localized: "common.share", defaultValue: "Share", table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: "square.and.arrow.up")
    }
    .accessibilityIdentifier("calendar.event.share")
  }
}
