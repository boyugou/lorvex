#if DEBUG
  import LorvexCore

  extension LorvexUIPreview {
    /// The Calendar stops that follow the default week: the day grid, the month
    /// grid, and the week with the Unplanned Tasks rail open beside it.
    ///
    /// The workspace reads its persisted presentation (`calendar.workspace.mode`,
    /// `calendar.workspace.planRail`) from the preview defaults when it is
    /// created, so each stop sets the keys and re-creates the workspace by
    /// passing through Today. The defaults end as they began, week with the
    /// rail hidden.
    @MainActor
    static func emitCalendarStops(store: AppStore) async {
      let stops: [(mode: CalendarPresentationMode, showsRail: Bool, name: String)] = [
        (.day, false, "calendar-day"),
        (.month, false, "calendar-month"),
        (.week, true, "calendar-rail"),
      ]
      for stop in stops {
        store.selection = .today
        previewDefaults.set(stop.mode.rawValue, forKey: "calendar.workspace.mode")
        previewDefaults.set(stop.showsRail, forKey: "calendar.workspace.planRail")
        try? await Task.sleep(for: .seconds(0.5))
        store.selection = .calendar
        try? await Task.sleep(for: .seconds(2.5))
        await emitStop(stop.name)
      }
      previewDefaults.set(false, forKey: "calendar.workspace.planRail")
    }
  }
#endif
