#if DEBUG
  import LorvexCore

  extension LorvexUIPreview {
    /// The Calendar stops that follow the default week: the day grid, the month
    /// grid, the week with the Unplanned Tasks rail open beside it, and the week
    /// with a timed task or a timed event open, whose block is drawn selected
    /// with its resize grips.
    ///
    /// The workspace reads its persisted presentation (`calendar.workspace.mode`,
    /// `calendar.workspace.planRail`) from the preview defaults when it is
    /// created, so each stop sets the keys and re-creates the workspace by
    /// passing through Today. The defaults end as they began, week with the
    /// rail hidden.
    @MainActor
    static func emitCalendarStops(store: AppStore) async {
      enum Opens { case nothing, timedTask, timedEvent }
      let stops: [(mode: CalendarPresentationMode, showsRail: Bool, opens: Opens, name: String)] = [
        (.day, false, .nothing, "calendar-day"),
        (.month, false, .nothing, "calendar-month"),
        (.week, true, .nothing, "calendar-rail"),
        (.week, false, .timedTask, "calendar-task"),
        (.week, false, .timedEvent, "calendar-event"),
      ]
      for stop in stops {
        store.selection = .today
        previewDefaults.set(stop.mode.rawValue, forKey: "calendar.workspace.mode")
        previewDefaults.set(stop.showsRail, forKey: "calendar.workspace.planRail")
        try? await Task.sleep(for: .seconds(0.5))
        store.selection = .calendar
        try? await Task.sleep(for: .seconds(2.5))
        switch stop.opens {
        case .nothing:
          break
        case .timedTask:
          if let task = store.scheduledTasks.first(where: {
            $0.plannedTime != nil && $0.status.isActionable
          }) {
            store.selectTaskFromList(task.id)
            try? await Task.sleep(for: .seconds(1))
          }
        case .timedEvent:
          // An event long enough to show both of its grips.
          if let event = store.calendarTimeline?.events.first(where: { event in
            guard event.editable, !event.isMultiDay, !event.supportsScopedMutation,
              let span = event.clockSpan(on: event.startDate), let end = span.end
            else { return false }
            return end - span.start >= 45
          }) {
            store.toggleCalendarEventSelection(event)
            try? await Task.sleep(for: .seconds(1))
          }
        }
        await emitStop(stop.name)
        store.selectedTaskID = nil
        store.selectedCalendarEventID = nil
      }
      previewDefaults.set(false, forKey: "calendar.workspace.planRail")
    }
  }
#endif
