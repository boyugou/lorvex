import AppKit
import LorvexCore
import UniformTypeIdentifiers

extension AppStore {
  /// Export the current calendar timeline window to an `.ics` file the user
  /// picks in a save panel — the macOS entry point for the `exportCalendarICS`
  /// core action (iOS, the MCP host, and the Shortcuts App Intent already wire
  /// it, but macOS had no caller). Exports the visible window
  /// (`calendarTimeline` bounds) to match the iOS export; a `nil` window lets
  /// the core export its current window.
  ///
  /// Reads the ICS through the core service, presents `NSSavePanel`, and writes
  /// the returned text to the chosen URL. Success and failure surface as a
  /// toast; a cancelled save panel is a no-op.
  func exportCalendarICSToFile() async {
    let ics: String
    do {
      ics = try await exportCalendarICS(
        from: calendarTimeline?.from, to: calendarTimeline?.to)
    } catch {
      toastMessage = Self.icsExportFailureMessage
      return
    }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType("com.apple.ical.ics") ?? .data]
    panel.nameFieldStringValue = "lorvex-calendar.ics"
    panel.canCreateDirectories = true
    panel.title = String(
      localized: "calendar.export_ics.action", defaultValue: "Export Calendar…",
      table: "Localizable",
      bundle: LorvexL10n.bundle)
    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      try ics.write(to: url, atomically: true, encoding: .utf8)
      toastMessage = String(
        localized: "calendar.export_ics.success", defaultValue: "Calendar exported.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    } catch {
      toastMessage = Self.icsExportFailureMessage
    }
  }

  private static var icsExportFailureMessage: String {
    String(
      localized: "calendar.export_ics.failed",
      defaultValue: "Couldn’t export the calendar.",
      table: "Localizable",
      bundle: LorvexL10n.bundle)
  }
}
