import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct MobileCalendarICSTransferable: Transferable {
  let content: String

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .mobileCalendarICS) { item in
      Data(item.content.utf8)
    }
    .suggestedFileName("lorvex-calendar.ics")
  }
}

private extension UTType {
  static let mobileCalendarICS = UTType("com.apple.ical.ics") ?? .data
}
