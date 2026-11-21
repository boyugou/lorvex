#if DEBUG
  import Foundation
  import LorvexCore
  import LorvexDomain

  extension MobileStore {
    func debugSeedSampleHabits(text: LorvexSampleText, day: (Int) -> Date, ymd: DateFormatter) async {
      let habits: [(String, String, String, String)] = [
        ("Morning run", "figure.run", "#FF9500", "After waking up"),
        ("Read 30 minutes", "book.fill", "#34C759", "Before bed"),
        ("Meditate", "brain.head.profile", "#5E5CE6", "Mid-morning"),
        ("Review the day", "checklist", "#0A84FF", "Evening"),
      ]
      var createdHabits: [String: LorvexHabit] = [:]
      for (name, icon, color, cue) in habits {
        // Give one habit a personal milestone goal so the goal picker + progress
        // surface have a set value to show.
        let milestoneTarget: Int? = (name == "Read 30 minutes") ? 30 : nil
        if let created = try? await core.createHabit(
          name: text(name), cue: text(cue), icon: icon, color: color, targetCount: 1,
          cadence: .daily, milestoneTarget: milestoneTarget)
        {
          createdHabits[name] = created
        }
      }
      if let run = createdHabits["Morning run"], let meditate = createdHabits["Meditate"],
        let read = createdHabits["Read 30 minutes"], let review = createdHabits["Review the day"]
      {
        try? await core.saveHabitRoutine(
          HabitRoutine(startMinutes: 420, habitIDs: [run.id, meditate.id]), for: .morning)
        try? await core.saveHabitRoutine(
          HabitRoutine(startMinutes: 1200, habitIDs: [read.id, review.id]), for: .evening)
      }
      // Backfill completion history so streaks (and the milestone bar) have a
      // real story: a 12-day streak toward the 14-day rung on the goal habit, a
      // shorter 3-day streak on another.
      if let read = createdHabits["Read 30 minutes"] {
        for offset in 0..<12 {
          _ = try? await core.completeHabit(id: read.id, date: ymd.string(from: day(-offset)))
        }
      }
      if let run = createdHabits["Morning run"] {
        for offset in 0..<3 {
          _ = try? await core.completeHabit(id: run.id, date: ymd.string(from: day(-offset)))
        }
      }
      // One archived habit, so the Habits screen's archived section has a row
      // to restore.
      if let journal = try? await core.createHabit(
        name: text("Evening journal"), cue: text("After dinner"), icon: "book.closed", color: "#AF52DE",
        targetCount: 1, cadence: .daily, milestoneTarget: nil)
      {
        _ = try? await core.updateHabit(
          id: journal.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
          archived: true)
      }
    }
  }
#endif
