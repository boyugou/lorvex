#if os(macOS) || os(iOS)
  import Foundation
  import LorvexDomain

  enum RoutineCopy {
    static var save: String {
      String(localized: "common.save", defaultValue: "Save", bundle: CoreL10n.bundle)
    }
    static var edit: String {
      String(localized: "common.edit", defaultValue: "Edit", bundle: CoreL10n.bundle)
    }
    static var done: String {
      String(localized: "common.done", defaultValue: "Done", bundle: CoreL10n.bundle)
    }
    static var skip: String {
      String(localized: "habits.skip.today", defaultValue: "Skip Today", bundle: CoreL10n.bundle)
    }
    static var unskip: String {
      String(localized: "habits.skip.undo", defaultValue: "Undo Skip", bundle: CoreL10n.bundle)
    }
    static var skipped: String {
      String(
        localized: "habits.detail.heatmap.legend.skipped", defaultValue: "Skipped",
        bundle: CoreL10n.bundle)
    }
    static var up: String {
      String(localized: "reorder.move_up", defaultValue: "Move Up", bundle: CoreL10n.bundle)
    }
    static var down: String {
      String(localized: "reorder.move_down", defaultValue: "Move Down", bundle: CoreL10n.bundle)
    }
    static var remove: String {
      String(localized: "recurrence.remove", defaultValue: "Remove", bundle: CoreL10n.bundle)
    }
    static var undoOne: String {
      String(localized: "habits.row.decrement", defaultValue: "Remove one", bundle: CoreL10n.bundle)
    }
    static var start: String {
      String(
        localized: "task_detail.picker.start_time", defaultValue: "Start Time",
        bundle: CoreL10n.bundle)
    }
    static var actions: String {
      String(
        localized: "command_palette.group.actions", defaultValue: "Actions", bundle: CoreL10n.bundle
      )
    }
    static var cancel: String {
      String(localized: "common.cancel", defaultValue: "Cancel", bundle: CoreL10n.bundle)
    }
    static var morning: String {
      String(
        localized: "today.routine.morning", defaultValue: "Morning routine", bundle: CoreL10n.bundle
      )
    }
    static var evening: String {
      String(
        localized: "today.routine.evening", defaultValue: "Evening routine", bundle: CoreL10n.bundle
      )
    }
    static var setUp: String {
      String(
        localized: "today.routine.setUp", defaultValue: "Set up routines", bundle: CoreL10n.bundle)
    }
    static var choose: String {
      String(
        localized: "today.routine.choose", defaultValue: "Choose habits", bundle: CoreL10n.bundle)
    }
    static var nothingDue: String {
      String(
        localized: "today.routine.nothingDue", defaultValue: "No habits due today",
        bundle: CoreL10n.bundle)
    }
    static var sameTime: String {
      String(
        localized: "today.routine.sameTime",
        defaultValue: "Choose different start times for the two routines.", bundle: CoreL10n.bundle)
    }

    static func name(_ period: HabitRoutinePeriod) -> String {
      period == .morning ? morning : evening
    }
    static func symbol(_ period: HabitRoutinePeriod) -> String {
      period == .morning ? "sunrise" : "moon.stars"
    }
  }
#endif
