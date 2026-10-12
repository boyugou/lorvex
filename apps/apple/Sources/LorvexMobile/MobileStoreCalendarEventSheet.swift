import LorvexCore
import SwiftUI

/// The sheet a tapped calendar event opens: its editor when Lorvex owns the
/// event, and its read-only detail (``MobileCalendarEventDetailSheet``) when a
/// device calendar does, since Lorvex mirrors those events and cannot change
/// them. Every surface that lists events presents this one sheet, so a tap
/// means the same everywhere.
struct MobileStoreCalendarEventSheet: View {
  let event: CalendarTimelineEvent
  @Bindable var store: MobileStore
  @Binding var isPresented: Bool

  var body: some View {
    if event.editable {
      MobileStoreEditCalendarEventSheet(event: event, store: store, isPresented: $isPresented)
    } else {
      MobileCalendarEventDetailSheet(event: event, isPresented: $isPresented)
    }
  }
}
