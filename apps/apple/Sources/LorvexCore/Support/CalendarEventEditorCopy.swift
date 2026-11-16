import Foundation

public enum CalendarEventEditorCopy {
  public static var addEndTime: String {
    String(localized: "calendar.editor.add_end", defaultValue: "Add end time", bundle: CoreL10n.bundle)
  }

  public static var removeEndTime: String {
    String(localized: "calendar.editor.remove_end", defaultValue: "Remove end time", bundle: CoreL10n.bundle)
  }
}
