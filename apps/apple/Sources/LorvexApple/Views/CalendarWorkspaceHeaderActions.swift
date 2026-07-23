import SwiftUI

struct CalendarWorkspaceHeaderActions: View {
  let createEvent: () -> Void

  var body: some View {
    Button(action: createEvent) {
      Image(systemName: "plus")
    }
    .workspaceHeaderActionStyle()
    .help(String(localized: "calendar.create_event", defaultValue: "Create Event", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityLabel(String(localized: "calendar.create_event", defaultValue: "Create Event", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityIdentifier("calendar.create")
  }
}
